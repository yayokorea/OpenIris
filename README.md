# OpenIris

OpenIris is the firmware part of the [EyeTrackVR Project](https://github.com/RedHawk989/EyeTrackVR).

The aim of this project is to provide a fast and performant firmware for streaming the eye data back to the PC for further processing and actual tracking.

---

## 🇰🇷 이 포크에서 달라진 점

> 원본 [EyeTrackVR/OpenIris](https://github.com/EyeTrackVR/OpenIris)를 포크해 아래 기능을 추가 / 개선했습니다.

### 🖥️ 컨트롤 웹페이지 전면 리뉴얼
- **한국어 UI** 및 **Glassmorphism(유리 반투명) 디자인**으로 전면 재작성
- WiFi 프로파일을 카드(칩) 형태로 최대 3개까지 저장·수정·삭제 가능
- **TX 전력 슬라이더** — dBm 수치를 실시간으로 확인하며 신호 세기 조절
- 토글 스위치 & 세그먼트 컨트롤로 각종 설정을 직관적으로 변경
- 우측 하단 **FAB 버튼** 하나로 핑 / 저장 / 재부팅 / 초기화 / OTA 접근
- 설정 변경 후 **토스트 알림**으로 성공·실패 즉시 확인
- 웹페이지 안에서 카메라 **MJPEG 미리보기** 지원 (별도 앱 불필요)
- **모바일 반응형** 레이아웃 — 스마트폰으로도 편하게 설정

### 🔄 무선 업데이트(OTA) 개선
- ESP32가 **직접 GitHub에서 펌웨어를 다운로드**해 CORS 오류 없이 업데이트 완료
- OTA 페이지 접속 시 **최신 릴리즈 목록을 자동으로 불러옴** (수동 입력 불필요)
- `yayokorea/OpenIris` 저장소가 기본값으로 설정되어 별도 입력 없이 바로 사용 가능
- 설정 패널에서 **정식 릴리즈 외 디버그 빌드도 선택적으로 표시** 가능
- 업데이트 진행률이 100%에 도달한 뒤 재부팅되어 진행 상태를 정확하게 확인 가능
- CI/CD를 통해 **OTA 전용 app-only `.bin` 파일**이 릴리즈마다 자동 제공

### 📡 상태 패널 정보 개선
- 상태 패널의 IP 주소란에 mDNS 호스트명(`openiris.local`) 대신 **실제 IPv4 주소** 표시
- IP를 직접 복사해 다른 앱이나 도구에서 바로 사용 가능

### 🌡️ 카메라 발열 감소
- 네트워크 전송 속도보다 빠르게 DMA가 동작하지 않도록 버퍼 전략 최적화
- 장시간 사용 시 ESP32 모듈의 **온도가 낮아지고 안정성이 향상**됨

---

# **NOTE**

This project is now archived and in upkeep mode. A new version, built from ground up, is being worked on here: https://github.com/lorow/openiris-espidf 

# Features

### Working right now

- [x] Basic stream in 60FPS at 248x248px in MJPEG in greyscale
- [x] A basic HTTP server with API
- [x] Basic control of the camera though API
- [x] Health checks
- [x] OTA updates
- [x] ROI selection for eye area
- [x] MDNS - so that the server itself will detect and communicate with the tracker without you doing anything. No need to configure IPs and stuff, it's automagic
- [x] Implementation of Preferences Lib for saving device settings (camera , MDNS, wifi configs etc )
- [x] CI/CD with github actions - so we can more seamlessly update the trackers
- [x] LED status patterns - so that you know what's going on without plugging the tracker in to the PC
- [x] Better OTA so that updates can be downloaded from github and pushed by the server to the tracker
- [x] Streaming over USB on boards that support it (ESP32S3 / XIAO ESP32S3 Sense thanks to XadE#2410 and Seaweed#4353

### TODO
- [ ] streaming over sockets instead of HTTP MJPEG for faster streams!
- [ ] better LED patterns 

# Docs: 
The "documentation" that was once present here was very old and outdated, we've moved from it being spread out in multiple repos to one place while also massively improving and expanding it, for the current info check this out:

https://docs.eyetrackvr.dev/
