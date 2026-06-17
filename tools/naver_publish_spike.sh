#!/usr/bin/env bash
# 네이버 카페 글쓰기 API spike (블로그 API는 2020-05 종료되어 카페 단독으로 확정)
# 목적: (1) 카페 글쓰기가 앱 소유자 토큰으로 검수 전 동작하는지
#       (2) 응답에 작성된 글 URL/식별자가 오는지
#       (docs/blog-publish-plan.md §5)
#
# 비밀값은 채팅/소스에 남기지 말고 환경변수로 주입해 실행하세요.
# 흐름: authorization code 교환 → (선택) 게시판 목록 조회 → 카페 글쓰기 → 응답 raw 출력
#
# ── 사용법 ─────────────────────────────────────────────
# 1) 인증코드 받기(브라우저, 사람만 가능):
#    https://nid.naver.com/oauth2.0/authorize?response_type=code&client_id=CID&redirect_uri=http%3A%2F%2Flocalhost&state=spike123
#    로그인·동의 후 redirect 주소창의 code= 값 복사
#
# 2) clubid 찾기:
#    내 카페(쓰기 권한 있는) PC웹에서 게시판 진입 → 주소/페이지에서 clubid(숫자) 확인
#    (menuid는 아래 [2] 게시판 목록 조회로 알아낼 수 있음)
#
# 3) 환경변수 설정 후 실행:
#    export NAVER_CLIENT_ID=xxxx  NAVER_CLIENT_SECRET=xxxx
#    export NAVER_REDIRECT='http://localhost'  NAVER_STATE='spike123'  NAVER_CODE='발급code'
#    export NAVER_CAFE_CLUBID=숫자clubid
#    # menuid를 이미 알면 지정(없으면 [2]만 보고 끝내고, 다시 menuid 넣어 재실행):
#    export NAVER_CAFE_MENUID=숫자menuid
#    bash tools/naver_publish_spike.sh
#
# ※ menuid 지정 시 카페에 실제 테스트 글이 1건 올라갑니다. 확인 후 삭제하세요.

set -u

: "${NAVER_CLIENT_ID:?NAVER_CLIENT_ID 필요}"
: "${NAVER_CLIENT_SECRET:?NAVER_CLIENT_SECRET 필요}"
: "${NAVER_REDIRECT:?NAVER_REDIRECT 필요}"
: "${NAVER_STATE:?NAVER_STATE 필요}"
: "${NAVER_CODE:?NAVER_CODE 필요}"
: "${NAVER_CAFE_CLUBID:?NAVER_CAFE_CLUBID 필요}"

echo "================ [1] access token 교환 ================"
TOKEN_JSON=$(curl -s -G "https://nid.naver.com/oauth2.0/token" \
  --data-urlencode "grant_type=authorization_code" \
  --data-urlencode "client_id=${NAVER_CLIENT_ID}" \
  --data-urlencode "client_secret=${NAVER_CLIENT_SECRET}" \
  --data-urlencode "code=${NAVER_CODE}" \
  --data-urlencode "state=${NAVER_STATE}")
echo "$TOKEN_JSON"
ACCESS_TOKEN=$(printf '%s' "$TOKEN_JSON" | grep -o '"access_token":"[^"]*"' | head -1 | sed 's/.*:"//;s/"$//')
if [ -z "${ACCESS_TOKEN}" ]; then
  echo ">> access_token 획득 실패. error/만료 확인. (code는 1회용·단기만료)"
  exit 1
fi
echo ">> access_token 획득 OK (길이 ${#ACCESS_TOKEN})"

echo
echo "================ [2] 게시판(메뉴) 목록 조회 → menuid 찾기 ================"
echo ">> 글 올릴 게시판의 menuid를 아래 목록에서 고른다."
curl -s -i -w '\n[HTTP_STATUS:%{http_code}]\n' \
  "https://openapi.naver.com/v1/cafe/${NAVER_CAFE_CLUBID}/menu/list.json" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}"

if [ -z "${NAVER_CAFE_MENUID:-}" ]; then
  echo
  echo ">> NAVER_CAFE_MENUID 미지정 → 글쓰기는 생략. 위 목록에서 menuid 정해 다시 실행하세요."
  echo "   (단, code는 만료되므로 브라우저 인증부터 다시 받아야 할 수 있음)"
  exit 0
fi

echo
echo "================ [3] 카페 글쓰기 ================"
echo ">> 응답 전체를 확인해 글 URL/식별자(articleid 등) 존재 여부를 본다."
curl -s -i -w '\n[HTTP_STATUS:%{http_code}]\n' \
  -X POST "https://openapi.naver.com/v1/cafe/${NAVER_CAFE_CLUBID}/menu/${NAVER_CAFE_MENUID}/articles" \
  -H "Authorization: Bearer ${ACCESS_TOKEN}" \
  --data-urlencode "subject=[spike] 카페 글쓰기 테스트" \
  --data-urlencode "content=spike 본문입니다. 확인 후 삭제하세요."

echo
echo "================ 끝 ================"
echo "확인 포인트:"
echo "  - [2]/[3] 호출이 200인가, 아니면 권한/검수 오류인가? → 검수 선행 필요 여부 확정"
echo "  - [3] 응답에 글 URL 또는 articleid 등 식별자가 있는가? → 발행 후 링크 제공 가능 여부"
echo "  - 한글 인코딩 정상인가(깨짐 사례 보고됨)"
echo "  - 결과를 docs/blog-publish-plan.md §2 '미확정'에 반영"
