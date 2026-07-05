// 발급받은 API 키를 여기에 입력하세요 (data.go.kr 마이페이지 → 개발계정 → 디코딩 키)
const String kDefaultKhoaApiKey = '98c36451233df29981610ab65de3363f1cdf9e8a556ad7cc95f554550642fcaf';

// AI 학습 데이터 업로드 (전용 Google 계정 Apps Script 웹앱). 배포 후 채우세요.
// 비어 있으면 업로드 기능은 자동 비활성화됩니다. (tools/nakkda_dataset_upload.gs 참고)
const String kDatasetUploadUrl =
    'https://script.google.com/macros/s/AKfycbwiZ-zQalk9ZTwCJoCW3r3YN_aCseyuIvSe2AVpg4-_ZsEe2YQRkAd6gBpnMeG2YmcS5w/exec';
const String kDatasetUploadToken = 'kDatasetUploadToken-CHANGE_ME_SECRET';
