# -*- coding: utf-8 -*-
# ============================================================
# 0. 필요한 모든 라이브러리 import (⚠️ 여기서는 "정의만" 하고, 무거운 일은 하지 않는다)
# ============================================================
import os
os.environ["CUDA_VISIBLE_DEVICES"] = "-1"  # GPU 완전 비활성화

import tempfile
from urllib.parse import unquote
from typing import Tuple, List, Dict, Any

import cv2
import numpy as np
import tensorflow as tf

import firebase_admin
from firebase_admin import firestore, storage
from firebase_functions import options, firestore_fn

print("=== Python Cloud Function 모듈 로드 ===")

# 🔹 리전 + 메모리 + 타임아웃 전역 설정
#   - 기본 메모리는 256MiB라서 TensorFlow + 모델 로딩 시 OOM 발생
#   - Grad-CAM처럼 무거운 작업이 있으니 최소 512MiB, 여유 있게 1GiB 사용
options.set_global_options(
    region=options.SupportedRegion.ASIA_NORTHEAST3,
    memory=options.MemoryOption.GB_4,  # 필요하면 MB_512로 낮춰도 됨
    timeout_sec=540,                   # 최대 9분
)

# 🔹 전역(캐시) 변수들: 처음 한 번만 초기화하고 이후 재사용
_db = None
_bucket = None
_grad_model = None
_IMG_SIZE = 224
_LAST_CONV_LAYER_NAME = "top_conv"

# 🔹 이 파일이 위치한 디렉토리 (모델 파일 경로용)
BASE_DIR = os.path.dirname(os.path.abspath(__file__))


# ============================================================
# 1. Firebase / 모델 Lazy 초기화 함수들
# ============================================================
def get_firebase() -> Tuple[firestore.Client, storage.bucket]:
    """
    Firebase Admin + Firestore + Storage 를 '처음 호출 시에만' 초기화하고,
    이후에는 전역 캐시를 재사용한다.
    """
    global _db, _bucket

    if _db is not None and _bucket is not None:
        return _db, _bucket

    print("🔧 Firebase 초기화 시작 (get_firebase 호출)")

    # ⚠️ Cloud Functions 환경에서는 별도 서비스키 JSON 없이도 ADC로 동작하므로
    #     initialize_app() 에 credential 을 안 넘겨도 됨.
    if not firebase_admin._apps:
        firebase_admin.initialize_app(
            options={
                "storageBucket": "deepfakekiller-672cf.firebasestorage.app"
            }
        )
        print("✅ firebase_admin.initialize_app() 완료")

    _db = firestore.client()
    _bucket = storage.bucket()
    print("✅ Firestore / Storage 클라이언트 준비 완료")

    return _db, _bucket


def get_grad_model() -> tf.keras.Model:
    """
    EfficientNet 기반 Grad-CAM용 모델을 '처음 호출 시에만' 로드하고 캐시한다.
    """
    global _grad_model

    if _grad_model is not None:
        return _grad_model

    print("🧩 Grad-CAM용 Keras 모델 로드 시작 (get_grad_model 호출)")

    # 모델 파일은 functions/ 폴더 안에 있다고 가정
    keras_model_path = os.path.join(BASE_DIR, "best_efficientnet_v13.keras")

    if not os.path.exists(keras_model_path):
        # 여기서 바로 Exception 을 던지면 함수 실행 시 에러가 보임 (healthcheck 시점이 아니라)
        raise FileNotFoundError(f"Keras 모델 파일을 찾을 수 없습니다: {keras_model_path}")

    base_model = tf.keras.models.load_model(keras_model_path)
    base_model.trainable = False

    last_conv_layer = base_model.get_layer(_LAST_CONV_LAYER_NAME)

    grad_model = tf.keras.models.Model(
        inputs=base_model.inputs,
        outputs=[last_conv_layer.output, base_model.output],
    )

    _grad_model = grad_model
    print("✅ Grad-CAM용 grad_model 구성 완료")

    return _grad_model


# ============================================================
# 2. Grad-CAM Helper 함수들
# ============================================================
def make_gradcam_heatmap(img_array: np.ndarray) -> np.ndarray:
    """
    img_array: (1,224,224,3) float32 [0,1]
    return   : heatmap (H, W) numpy, 0~1
    """
    grad_model = get_grad_model()  # ✅ 여기서 필요할 때만 모델 로드

    img_tensor = tf.convert_to_tensor(img_array)

    with tf.GradientTape() as tape:
        # Functional 모델은 보통 리스트 입력 구조를 기대하므로 [img_tensor]로 전달
        conv_outputs, predictions = grad_model([img_tensor], training=False)

        # 혹시 list/tuple로 나오는 경우 방어
        if isinstance(conv_outputs, (list, tuple)):
            conv_outputs = conv_outputs[0]
        if isinstance(predictions, (list, tuple)):
            predictions = predictions[0]

        # binary classification: output[:, 0] = fake 확률(sigmoid)
        loss = predictions[:, 0]

    grads = tape.gradient(loss, conv_outputs)              # (1, H, W, C)
    pooled_grads = tf.reduce_mean(grads, axis=(0, 1, 2))   # (C,)

    conv_outputs = conv_outputs[0]                         # (H, W, C)
    heatmap = tf.zeros(shape=conv_outputs.shape[0:2])

    # 채널별 가중합
    for i in range(conv_outputs.shape[-1]):
        heatmap += pooled_grads[i] * conv_outputs[:, :, i]

    # ReLU + 정규화
    heatmap = tf.nn.relu(heatmap)
    heatmap /= (tf.reduce_max(heatmap) + 1e-8)

    return heatmap.numpy()


def generate_real_grad_cam(original_image_path: str) -> str:
    """
    다운로드된 원본 이미지로 Grad-CAM 결과 이미지를 생성하고 저장.
    return: 생성된 Grad-CAM 이미지의 로컬 경로
    """
    print("🧠 [작업 1/3] Grad-CAM 분석 시작...")

    original_img = cv2.imread(original_image_path)
    if original_img is None:
        raise ValueError(f"이미지를 읽을 수 없습니다: {original_image_path}")

    h, w, _ = original_img.shape

    # RGB 변환 + 224x224 + [0,1] 정규화
    img_rgb = cv2.cvtColor(original_img, cv2.COLOR_BGR2RGB)
    img_rgb = cv2.resize(img_rgb, (_IMG_SIZE, _IMG_SIZE))
    img = img_rgb.astype(np.float32) / 255.0
    img = np.expand_dims(img, axis=0)  # (1,224,224,3)

    # Grad-CAM heatmap 계산
    heatmap = make_gradcam_heatmap(img)

    # 원본 크기로 resize + 컬러맵 적용
    heatmap_resized = cv2.resize(heatmap, (w, h))
    heatmap_uint8 = np.uint8(255 * heatmap_resized)
    heatmap_color = cv2.applyColorMap(heatmap_uint8, cv2.COLORMAP_JET)

    # 원본에 overlay
    alpha = 0.4
    superimposed_img = cv2.addWeighted(original_img, 1 - alpha, heatmap_color, alpha, 0)
    superimposed_img = np.clip(superimposed_img, 0, 255).astype(np.uint8)

    # 저장 경로
    root, ext = os.path.splitext(original_image_path)
    grad_cam_path = f"{root}_gradcam{ext}"
    cv2.imwrite(grad_cam_path, superimposed_img)

    print(f"✅ Grad-CAM 이미지 생성 완료: {grad_cam_path}")
    return grad_cam_path


def upload_image_to_storage(local_file_path: str, document_id: str) -> str:
    """
    결과 이미지를 Storage의 gradcams/{document_id}/ 폴더에 업로드하고 public URL 반환.
    """
    db, bucket = get_firebase()  # bucket 사용을 위해 (db는 여기선 안 써도 됨)
    _ = db

    print("📤 [작업 2/3] 결과 이미지를 Storage에 업로드 중...")
    destination_blob_name = f"gradcams/{document_id}/{os.path.basename(local_file_path)}"

    blob = bucket.blob(destination_blob_name)
    blob.upload_from_filename(local_file_path)
    blob.make_public()

    print(f"✅ 업로드 완료. 새 경로: {destination_blob_name}")
    return blob.public_url


def update_firestore_with_gradcam_url(
    doc_ref,
    key_frames_data: List[Dict[str, Any]],
    frame_index: int,
    grad_cam_url: str,
) -> None:
    """
    Firestore 문서의 key_frames[frame_index].gradCamUrl 필드에 URL 추가 후 업데이트.
    """
    print("📝 [작업 3/3] Firestore 문서를 새 URL로 업데이트 중...")
    key_frames_data[frame_index]["gradCamUrl"] = grad_cam_url
    doc_ref.update({"key_frames": key_frames_data})
    print("✅ 문서 업데이트 완료!")


# ============================================================
# 3. Firestore 트리거 함수
# ============================================================
@firestore_fn.on_document_created(document="call_records/{documentId}")
def on_call_record_created(event: firestore_fn.Event[firestore_fn.Change]) -> None:
    """
    call_records/{documentId} 문서가 새로 생성되면 자동 실행.

    동작:
      1) key_frames 배열에서 각 frame의 url을 읽고
      2) Storage에서 이미지 다운로드
      3) Grad-CAM 생성
      4) gradcams/{documentId}/ 경로에 업로드
      5) key_frames[i].gradCamUrl 필드를 새 URL로 업데이트
    """
    document_id = event.params["documentId"]
    print("\n===== NEW TRIGGER: on_call_record_created =====")
    print(f"   - 감지된 문서 ID: {document_id}")

    try:
        db, bucket = get_firebase()
        _ = bucket  # bucket은 아래에서 blob() 할 때 사용

        # event.data 는 새로 생성된 문서 스냅샷
        record_data = event.data.to_dict()
        if record_data is None:
            raise Exception("🚨 event.data가 비어 있습니다.")

        key_frames = record_data.get("key_frames")
        if not key_frames:
            raise Exception("🚨 문서에 'key_frames' 필드가 없습니다.")

        print(f"   - key_frames 개수: {len(key_frames)}")

        doc_ref = db.collection("call_records").document(document_id)

        for i, frame_data in enumerate(key_frames):
            print(f"\n--- 프레임 {i + 1}/{len(key_frames)} 처리 시작 ---")

            image_url = frame_data.get("url")
            if not image_url:
                print("⚠️ 이 프레임에는 'url'이 없습니다. 건너뜁니다.")
                continue

            # Storage 경로 파싱
            try:
                file_path_encoded = image_url.split("/o/")[1].split("?")[0]
            except Exception:
                raise ValueError(f"URL 형식이 예상과 다릅니다: {image_url}")

            file_path = unquote(file_path_encoded)
            print(f"   - Storage 경로: {file_path}")

            # 원본 이미지 /tmp 로 다운로드
            blob = storage.bucket().blob(file_path)
            temp_dir = tempfile.gettempdir()
            downloaded_file_path = os.path.join(temp_dir, os.path.basename(file_path))
            blob.download_to_filename(downloaded_file_path)
            print(f"✅ 원본 이미지 다운로드 완료: {downloaded_file_path}")

            # Grad-CAM 생성
            grad_cam_file = generate_real_grad_cam(downloaded_file_path)

            # Storage에 업로드
            new_grad_cam_url = upload_image_to_storage(grad_cam_file, document_id)

            # Firestore 업데이트
            update_firestore_with_gradcam_url(doc_ref, key_frames, i, new_grad_cam_url)

        print("\n=======================================================")
        print(f"🎉 문서 '{document_id}'의 모든 프레임 처리 완료!")
        print("=======================================================\n")

    except Exception as e:
        print(f"\n❌ 문서 '{document_id}' 처리 중 에러 발생: {e}\n")
