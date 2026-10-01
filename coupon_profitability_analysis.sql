-- 주의: PART 0에는 TRUNCATE / LOAD DATA LOCAL INFILE이 포함되어 있습니다.
-- 이미 데이터가 적재된 DB에서는 PART 0을 제외하고 PART 1부터 실행하세요.
-- '순수익'은 원가 미반영 수익성 대리 지표입니다. (할인·GST 반영, 배송료 제외)
-- 쿠폰상태가 Clicked인 거래는 할인 미적용으로 처리했습니다.
-- 쿠폰의존도와 시뮬레이션은 상품라인 기준으로 계산했습니다.

-- =======================================================================================================
-- 프로젝트명 : '우리 쿠폰, 진짜 남는 장사인가?' - 쿠폰 프로모션 수익성 & 고객 세그먼트 분석

-- [분석용 '마진' 지표 정의 | 금액 단위: USD($)]
-- 데이터셋에는 상품 원가(COGS)가 제공되지 않으므로 본 프로젝트의 '마진/마진율'은
-- 회계상 Gross Margin 또는 순이익을 의미하지 않는다.
-- 본 프로젝트에서는 고객·카테고리·세그먼트 간 상대적 수익성을 비교하기 위해
-- 다음과 같이 '분석용 마진 지표'를 정의한다.
--
-- 1) 할인 전 매출 = 평균금액 × 수량
-- 2) 실질금액 = Used 상태에만 쿠폰 할인 적용 후 금액
-- 3) 순수익(분석용) = 실질금액 × (1 - GST)
-- 4) 마진율(분석용) = SUM(순수익) / SUM(할인 전 매출) × 100
--
-- 배송료는 데이터 명세만으로 고객 부담액인지 회사 비용인지 귀속을 확정하기 어려워
-- 핵심 마진 계산에서 제외한다.
-- 따라서 SQL/Tableau의 '순수익', '마진합', '마진율', '마진ROAS'는 모두 위 정의에 따른
-- 분석용 지표이며 실제 회계상 이익으로 해석하지 않는다.
-- Clicked는 할인 적용 여부가 명시되지 않아 보수적으로 할인 미적용으로 처리한다.
--
-- 활용 데이터셋 리스트
-- Customer_info (고객 마스터 테이블)
-- Onlinesales_info (거래 메인 테이블)
-- Discount_info (쿠폰 마스터 테이블)
-- Marketing_info (일별 마케팅비 테이블)
-- Tax_info (세금 마스터 테이블)
-- =======================================================================================================


-- =======================================================================================================
-- PART 0. DB/테이블 생성 및 데이터 적재
-- =======================================================================================================

CREATE DATABASE IF NOT EXISTS ecommerce_crm_analysis DEFAULT CHARSET=utf8mb4;
USE ecommerce_crm_analysis;
SET GLOBAL local_infile = 1;

-- 1) Onlinesales_info (거래 메인 테이블)
CREATE TABLE IF NOT EXISTS onlinesales_info (
	고객ID VARCHAR(20),
    거래ID VARCHAR(20),
    거래날짜 DATE,
    제품ID VARCHAR(20),
	제품카테고리 VARCHAR(50),
    수량 INT,
    평균금액 DECIMAL(10,2),
    배송료 DECIMAL(10,2),
    쿠폰상태 VARCHAR(20)
) DEFAULT CHARSET=utf8mb4;

TRUNCATE TABLE onlinesales_info;
LOAD DATA LOCAL INFILE './data/Onlinesales_info.csv'
INTO TABLE onlinesales_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 2) Customer_info (고객 마스터 테이블) 
CREATE TABLE IF NOT EXISTS customer_info (
	고객ID VARCHAR(20),
    성별 VARCHAR(5),
    고객지역 VARCHAR(50),
    가입기간 INT
) DEFAULT CHARSET=utf8mb4;

TRUNCATE TABLE customer_info;
LOAD DATA LOCAL INFILE './data/Customer_info.csv'
INTO TABLE customer_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 3) Discount_info (쿠폰 마스터 테이블) 
CREATE TABLE IF NOT EXISTS discount_info (
	월 VARCHAR(10),
    제품카테고리 VARCHAR(50),
    쿠폰코드 VARCHAR(20),
    할인율 INT
) DEFAULT CHARSET=utf8mb4;

TRUNCATE TABLE discount_info;
LOAD DATA LOCAL INFILE './data/Discount_info.csv'
INTO TABLE discount_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n' 
IGNORE 1 ROWS;

-- 4) Marketing_info (일별 마케팅비 테이블)
CREATE TABLE IF NOT EXISTS marketing_info (
	날짜 DATE,
    오프라인비용 INT,
    온라인비용 DECIMAL(10,2)
) DEFAULT CHARSET=utf8mb4;

TRUNCATE TABLE marketing_info;
LOAD DATA LOCAL INFILE './data/Marketing_info.csv'
INTO TABLE marketing_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 5) Tax_info (세금 마스터 테이블)
CREATE TABLE IF NOT EXISTS tax_info (
	제품카테고리 VARCHAR(50),
	GST DECIMAL(5,2)
) DEFAULT CHARSET=utf8mb4;

TRUNCATE TABLE tax_info;
LOAD DATA LOCAL INFILE './data/Tax_info.csv'
INTO TABLE tax_info
CHARACTER SET utf8mb4
FIELDS TERMINATED BY ',' ENCLOSED BY '"' LINES TERMINATED BY '\n'
IGNORE 1 ROWS;

-- 적재 건수 확인 (원본 기준 : 고객 1,468 / 쿠폰 204 / 마케팅 365 / 세금 20 / 거래 52,924)
SELECT 'customer_info' AS 테이블, COUNT(*) AS 행수 FROM customer_info
UNION ALL
SELECT 'discount_info', COUNT(*) FROM discount_info
UNION ALL
SELECT 'marketing_info', COUNT(*) FROM marketing_info
UNION ALL
SELECT 'tax_info', COUNT(*) FROM tax_info
UNION ALL
SELECT 'onlinesales_info', COUNT(*) FROM onlinesales_info;


-- =======================================================================================================
-- PART 1. 데이터 정합성 검토 (EDA)
-- =======================================================================================================

-- 1-1) 개별 테이블 컬럼 값 검증 -------------------------------------------------------------------------------

-- customer_info
SELECT DISTINCT 성별 FROM customer_info;
SELECT DISTINCT 고객지역 FROM customer_info;
SELECT MIN(가입기간), MAX(가입기간), AVG(가입기간) FROM customer_info;

-- onlinesales_info
SELECT DISTINCT 제품카테고리 FROM onlinesales_info ORDER BY 1;
SELECT MIN(거래날짜), MAX(거래날짜) FROM onlinesales_info;
SELECT MIN(평균금액), MAX(평균금액) FROM onlinesales_info;

SELECT 수량 FROM onlinesales_info
WHERE 수량 <= 0 OR 수량 IS NULL;  -- 이상치 없음

SELECT 평균금액 FROM onlinesales_info
WHERE 평균금액 <= 0 OR 평균금액 IS NULL;  -- 이상치 없음

SELECT 쿠폰상태, COUNT(*) AS 건수 FROM onlinesales_info 
GROUP BY 쿠폰상태
ORDER BY 건수 DESC;
-- Used 17,904 / Clicked 26,926 / Not Used 8,094
-- 쿠폰상태 'Clicked'(전체의 50.9%)는 정의가 명시되어 있지않음
-- 단가(평균금액) 비교 검증 결과, 세 상태 간 유의미한 차이가 없어(51.8 ~ 52.6)
-- 할인 반영 여부를 판단할 근거를 찾지 못해 보수적으로 'Used'가 아닌 것으로 처리함 (할인 미적용)

SELECT o.제품카테고리, COUNT(*) AS 건수
FROM onlinesales_info o
GROUP BY o.제품카테고리
ORDER BY 건수 DESC;

-- discount_info
SELECT DISTINCT 제품카테고리 FROM discount_info ORDER BY 1;
SELECT DISTINCT 월 FROM discount_info;
SELECT DISTINCT 쿠폰코드 FROM discount_info;
SELECT MIN(할인율), MAX(할인율) FROM discount_info; 

-- marketing_info
SELECT MIN(날짜), MAX(날짜) FROM marketing_info;
SELECT MIN(오프라인비용), MAX(오프라인비용) FROM marketing_info;
SELECT MIN(온라인비용), MAX(온라인비용) FROM marketing_info;
SELECT COUNT(*) FROM marketing_info WHERE 오프라인비용 < 0 OR 온라인비용 < 0;
SELECT COUNT(*) FROM marketing_info WHERE 날짜 IS NULL;

-- tax_info
SELECT DISTINCT 제품카테고리 FROM tax_info;
SELECT MIN(GST), MAX(GST) FROM tax_info;

-- 1-2) 테이블 간 정합성 검증 =================================================================================

-- (1) onlinesales_info & customer_info : 고객ID 매칭 확인
SELECT DISTINCT o.고객ID
FROM onlinesales_info o
LEFT JOIN customer_info c ON o.고객ID = c.고객ID
WHERE c.고객ID IS NULL;  -- 없음

-- (2) onlinesales_info -> discount_info : 매칭 안되는 카테고리 확인
SELECT DISTINCT o.제품카테고리
FROM onlinesales_info o
LEFT JOIN discount_info d ON o.제품카테고리 = d.제품카테고리
WHERE d.제품카테고리 IS NULL;
-- Fun, Backpacks, Google, More Bags -> discount_info에 쿠폰 자체가 없는 카테고리

-- (3) discount_info -> onlinesales_info : 반대방향으로도 매칭 카테고리 확인
SELECT DISTINCT d.제품카테고리
FROM discount_info d
LEFT JOIN onlinesales_info o ON d.제품카테고리 = o.제품카테고리 
WHERE o.제품카테고리 IS NULL;
-- 'Notebooks' 확인

-- (3-1) Notebooks vs Notebooks & Journals : 표기 오류인지 별개의 카테고리인지 검증
SELECT * FROM discount_info WHERE 제품카테고리 = 'Notebooks';
SELECT * FROM discount_info WHERE 제품카테고리 = 'Notebooks & Journals';
-- 12개월 전부 겹치고, 쿠폰코드 체계도 별도로 독립 운영 (NOTES.. vs NJ..)
-- 표기 오류가 아닌 별개의 카테고리로 판단하여 통합하지 않음
-- onlinesales_info에 'Notebooks' 카테고리 거래 자체가 없으므로 마진 계산에 영향없음

-- (4) onlinesales_info -> tax_info : 매칭 안되는 카테고리 확인
SELECT DISTINCT o.제품카테고리
FROM onlinesales_info o
LEFT JOIN tax_info t ON o.제품카테고리 = t.제품카테고리
WHERE t.제품카테고리 IS NULL;

-- (5) discount_info에 없는 4개 카테고리 중 쿠폰 Used 건수 확인 (실제 영향도 산정)
SELECT o.제품카테고리, COUNT(*) AS 건수
FROM onlinesales_info o
WHERE o.제품카테고리 IN ('Fun', 'Backpacks', 'Google', 'More Bags')
	AND o.쿠폰상태 = 'Used'
GROUP BY o.제품카테고리;
-- 합계 126건 / 전체 거래 52,924건 대비 0.24% 수준 -> COALESCE(할인율,0)로 처리, 별도 조치 불필요


-- =======================================================================================================
-- PART 2. 분석용 VIEW 체인
-- 2단계~8단계 CTE 설계를 VIEW로 저장하여 이후 여러 최종 조회/CSV 추출 시 반복없이 재사용
-- 마지막 액션 임팩트 시뮬레이션은 단계 번호 없는 별도 파트로 아래에 이어짐
-- =======================================================================================================

-- [2단계] 거래별 분석용 마진 계산 -------------------------------------------------------------------------------
CREATE OR REPLACE VIEW 거래_할인정보 AS
SELECT
	o.고객ID,
	o.거래ID,
	o.거래날짜,
	DATE_FORMAT(o.거래날짜, '%b') AS 월,
	o.제품ID,
	o.제품카테고리,
	o.수량,
	o.평균금액,
	o.배송료,
	o.쿠폰상태,
	d.할인율,
	t.GST	
FROM onlinesales_info o
LEFT JOIN discount_info d
	ON DATE_FORMAT(o.거래날짜, '%b') = d.월 AND o.제품카테고리 = d.제품카테고리
LEFT JOIN tax_info t
	ON o.제품카테고리 = t.제품카테고리;
    
CREATE OR REPLACE VIEW 거래_마진계산 AS
SELECT *,
	CASE WHEN 쿠폰상태 = 'Used'
		THEN (평균금액 * 수량 * (1 - COALESCE(할인율,0)/100))
		ELSE (평균금액 * 수량) 
	END AS 실질금액
FROM 거래_할인정보;

CREATE OR REPLACE VIEW 거래_순수익계산 AS
SELECT *, 실질금액 * (1 - GST) AS 순수익
FROM 거래_마진계산;
-- 배송료는 고객부담/회사 원가 여부가 데이터상 불명확하여 핵심 수익성 지표에서는 제외
-- 거래ID당 배송료가 1회만 발생하는 주문 단위 값임을 별도 검증함 


-- [3단계] 거래 단위 -> 고객 단위 집계 --------------------------------------------------------------------------
CREATE OR REPLACE VIEW 주문별_합계 AS
SELECT 고객ID, 거래ID, SUM(실질금액) AS 주문금액
FROM 거래_순수익계산
GROUP BY 고객ID, 거래ID;

CREATE OR REPLACE VIEW 고객별_주문요약 AS
SELECT 고객ID, AVG(주문금액) AS 평균_객단가
FROM 주문별_합계
GROUP BY 고객ID;

-- 주문 단위 F(총주문건수)를 별도 컬럼으로 둔다. 나머지 컬럼명은 Tableau 호환을 위해 그대로 사용.
-- '총거래건수'의 실제 의미는 상품라인 수이며, RFM의 F에는 총주문건수를 사용한다.
-- 고객별 GROUP BY 안에서는 COUNT(DISTINCT 거래ID)가 (고객ID, 거래ID) 고유 조합의 주문 수이다.
CREATE OR REPLACE VIEW 고객별집계 AS
SELECT
	s.고객ID,
	COUNT(s.거래ID) AS 총거래건수,  -- 상품라인 수(주문 수 아님)
	SUM(CASE WHEN s.쿠폰상태 = 'Used' THEN 1 ELSE 0 END) AS 쿠폰사용_거래건수, -- Used 상품라인 수
	SUM(CASE WHEN s.쿠폰상태 = 'Used' THEN 1 ELSE 0 END) * 1.0 / COUNT(s.거래ID) * 100 AS 쿠폰사용비중, -- 상품라인 기준
	SUM(s.순수익) AS 총순수익,
	COUNT(DISTINCT s.거래ID) AS 총주문건수 -- RFM의 F
FROM 거래_순수익계산 s
GROUP BY s.고객ID;

CREATE OR REPLACE VIEW 고객별_Recency AS
SELECT
	고객ID,
	MAX(거래날짜) AS 마지막구매일,
	DATEDIFF((SELECT MAX(거래날짜) FROM onlinesales_info), MAX(거래날짜)) AS Recency
FROM 거래_순수익계산
GROUP BY 고객ID;


-- [4단계] 쿠폰의존도 세그먼트 분류 ------------------------------------------------------------------------------
-- 0%(무의존)/100%(완전의존)는 명확한 경계로 분리, 1~99%는 NTILE(3)으로 인원수 3등분

CREATE OR REPLACE VIEW 중간구간_분위 AS
SELECT c.*, q.평균_객단가,
	NTILE(3) OVER (ORDER BY c.쿠폰사용비중, c.고객ID) AS 분위
FROM 고객별집계 c
LEFT JOIN 고객별_주문요약 q ON c.고객ID = q.고객ID 
WHERE c.쿠폰사용비중 > 0 AND c.쿠폰사용비중 < 100;

-- UNION ALL 양쪽의 컬럼 개수·순서를 명시적으로 일치시킨다.
-- 평균_객단가/세그먼트 등 컬럼명은 Tableau 호환을 위해 유지.
CREATE OR REPLACE VIEW 고객_세그먼트 AS
SELECT
	c.고객ID, c.총거래건수, c.쿠폰사용_거래건수, c.쿠폰사용비중, c.총순수익,
	q.평균_객단가,
	CASE
		WHEN c.쿠폰사용비중 = 0 THEN '무의존'
		WHEN c.쿠폰사용비중 = 100 THEN '완전의존'
	END AS 세그먼트,
	c.총주문건수 
FROM 고객별집계 c
LEFT JOIN 고객별_주문요약 q ON c.고객ID = q.고객ID
WHERE c.쿠폰사용비중 = 0 OR c.쿠폰사용비중 = 100

UNION ALL
SELECT
	고객ID, 총거래건수, 쿠폰사용_거래건수, 쿠폰사용비중, 총순수익,
	평균_객단가,
	CASE 분위
		WHEN 1 THEN '저의존'
		WHEN 2 THEN '중의존'
		WHEN 3 THEN '고의존'
	END AS 세그먼트,
	총주문건수 
FROM 중간구간_분위;


-- [5단계] 쿠폰의존 세그먼트 x 카테고리 선호지수 --------------------------------------------------------------------
-- 4단계에서 만든 '쿠폰의존 세그먼트'별 카테고리 비중을 '전체 평균 대비'로 정규화하여
-- 진짜 선호 카테고리를 식별

CREATE OR REPLACE VIEW 세그먼트별_카테고리 AS
SELECT 
	s.세그먼트, t.제품카테고리, COUNT(*) AS 거래건수
FROM 고객_세그먼트 s 
LEFT JOIN 거래_순수익계산 t ON s.고객ID = t.고객ID 
GROUP BY s.세그먼트, t.제품카테고리;

CREATE OR REPLACE VIEW 세그먼트별_카테고리_비중 AS
SELECT
	세그먼트, 제품카테고리, 거래건수,
	SUM(거래건수) OVER (PARTITION BY 세그먼트) AS 세그먼트전체거래건수,
	거래건수 * 100.0 / SUM(거래건수) OVER (PARTITION BY 세그먼트) AS 카테고리비중
FROM 세그먼트별_카테고리;

CREATE OR REPLACE VIEW 전체_카테고리_비중 AS
SELECT
	제품카테고리,
	COUNT(*) AS 전체거래건수,
	COUNT(*) * 100.0 / SUM(COUNT(*)) OVER () AS 전체카테고리비중
FROM 거래_순수익계산
GROUP BY 제품카테고리;

CREATE OR REPLACE VIEW 세그먼트_지수 AS
SELECT
	s.세그먼트, s.제품카테고리, s.거래건수,
	s.카테고리비중 AS 세그먼트내비중,
	t.전체카테고리비중,
	s.카테고리비중 / t.전체카테고리비중 * 100 AS 선호지수
FROM 세그먼트별_카테고리_비중 s
LEFT JOIN 전체_카테고리_비중 t ON s.제품카테고리 = t.제품카테고리;
-- RFM 라이프사이클까지 함께 교차하지 않은 이유 : 쿠폰의존(5종) RFM(6종) 카테고리(20종)를 다 곱하면
-- 최대 600칸이 생겨, 완전의존(37개 상품라인)에서 이미 겪은 '표본이 작아 지수가 튄다'는 문제가 훨씬 심해짐
-- 두 세그먼트 축은 서로 다른 질문에 쓰이도록 역할을 분리함
-- 5단계는 '무엇을 사는가'(추천/프로모션 설계용), 7-2단계는 '왜 마진이 낮은가'(원인 진단용)


-- [6단계] RFM 라이프사이클 세그먼트 -----------------------------------------------------------------------------
-- F(총주문건수=고객별 고유 주문 수), M(총순수익)은 3단계 산출물 재사용, R(Recency)만 신규 계산

CREATE OR REPLACE VIEW 고객_RFM_통합 AS
SELECT
	a.고객ID,
	a.총주문건수 AS F_거래건수, -- 별칭은 Tableau 호환을 위해 유지, 실제 의미는 고유 주문 수
	a.총순수익 AS M_순수익,
	r.Recency AS R_경과일수,
	c.가입기간,
	s.세그먼트 AS 쿠폰의존세그먼트
FROM 고객별집계 a
LEFT JOIN 고객별_Recency r ON a.고객ID = r.고객ID
LEFT JOIN customer_info c ON a.고객ID = c.고객ID
LEFT JOIN 고객_세그먼트 s ON a.고객ID = s.고객ID;

CREATE OR REPLACE VIEW RFM_분위 AS
SELECT
	고객ID, F_거래건수, M_순수익, R_경과일수, 가입기간, 쿠폰의존세그먼트,
	NTILE(3) OVER (ORDER BY F_거래건수, 고객ID) AS F_분위, -- 동점 시 고객ID를 보조 정렬키로 사용
	NTILE(3) OVER (ORDER BY M_순수익, 고객ID) AS M_분위,
	NTILE(3) OVER (ORDER BY R_경과일수 DESC, 고객ID) AS R_분위
FROM 고객_RFM_통합;

CREATE OR REPLACE VIEW RFM_가입구분 AS
SELECT
	고객ID, F_거래건수, M_순수익, R_경과일수,
	F_분위, M_분위, R_분위,
	쿠폰의존세그먼트, 가입기간,
	CASE WHEN 가입기간 <= 12 THEN '신규' 
	ELSE '기존' END AS 가입구분
FROM RFM_분위;

CREATE OR REPLACE VIEW RFM_라이프사이클 AS
SELECT *,
	CASE
		WHEN RFM_합산점수 <= 4 THEN '낮음'
		WHEN RFM_합산점수 <= 7 THEN '중간'
		ELSE '높음'
	END AS RFM등급
FROM (
	SELECT *, (F_분위 + M_분위 + R_분위) AS RFM_합산점수
	FROM RFM_가입구분
) AS 임시;
-- 점수범위(3~9)의 양 끝에서 각 2단계씩을 극단군(낮음/높음)으로, 나머지를 중간군으로 정의
-- 6개 라이프사이클 세그먼트(신규/기존 x 낮음/중간/높음)


-- [7단계] 카테고리 진짜 수익성 - 전체 & RFM 세그먼트별 --------------------------------------------------------------

-- 7-1) 카테고리 x 월 / 연간 전체 수익성
CREATE OR REPLACE VIEW 카테고리월별_수익성 AS
SELECT
	제품카테고리, 월,
	SUM(평균금액 * 수량) AS 매출합,
	SUM(순수익) AS 마진합,
	SUM(순수익) / SUM(평균금액 * 수량) * 100 AS 마진율
FROM 거래_순수익계산
GROUP BY 제품카테고리, 월;

CREATE OR REPLACE VIEW 카테고리별_연간수익성 AS
SELECT
	제품카테고리,
	SUM(평균금액 * 수량) AS 매출합,
	SUM(순수익) AS 마진합,
	SUM(순수익) / SUM(평균금액 * 수량) * 100 AS 마진율
FROM 거래_순수익계산
GROUP BY 제품카테고리;
-- 마진율은 반드시 SUM(마진)/SUM(매출)로 계산(가중평균)
-- AVG(마진율)은 거래량이 적은 월에 과도한 가중치를 주는 단순평균이라 왜곡이 발생하므로 사용하지않음

-- 7-2) RFM 라이프사이클 세그먼트 x 카테고리 마진갭 분석
-- '이탈위험 고객(기존+RFM 낮음)이 저마진 카테고리에 몰려있는가, 
-- 아니면 같은 카테고리 안에서도 할인을 더 받는가'를 분리해서 확인 (카테고리 믹스효과 vs 행태 효과)

CREATE OR REPLACE VIEW 라이프사이클_카테고리_수익성 AS
SELECT
	l.가입구분,
	l.RFM등급,
	t.제품카테고리,
	SUM(t.평균금액 * t.수량) AS 매출합,
	SUM(t.순수익) AS 마진합
FROM RFM_라이프사이클 l
LEFT JOIN 거래_순수익계산 t ON l.고객ID = t.고객ID
GROUP BY l.가입구분, l.RFM등급, t.제품카테고리;

CREATE OR REPLACE VIEW 라이프사이클_마진갭분석 AS
SELECT
	l.가입구분, 
	l.RFM등급,
	SUM(l.마진합) / SUM(l.매출합) * 100 AS 실제마진율,
	SUM(l.매출합 * c.마진율) / SUM(l.매출합) AS 카테고리믹스기준예상마진율
FROM 라이프사이클_카테고리_수익성 l
LEFT JOIN 카테고리별_연간수익성 c ON l.제품카테고리 = c.제품카테고리
GROUP BY l.가입구분, l.RFM등급;
-- 실제마진율 - 카테고리믹스기준예상마진율(갭)이 음수이면
-- 해당 세그먼트의 카테고리 구성을 감안한 기대치보다 분석용 마진율이 낮게 나타났음을 의미한다.
-- 이 차이는 할인 이용 패턴과 관련될 가능성을 보여주는 진단 지표이며, 인과관계를 직접 증명하지는 않는다.
-- 핵심 결과: 이탈위험 고객(기존+RFM 낮음) 그룹의 마진갭은 약 -0.401%p.


-- [8단계] 마케팅비 대비 매출 효율 --------------------------------------------------------------------------------
CREATE OR REPLACE VIEW 월별_마케팅비_합계 AS
SELECT
	DATE_FORMAT(날짜, '%b') AS 월,
	SUM(오프라인비용) AS 오프라인비용합계,
	SUM(온라인비용) AS 온라인비용합계,
	SUM(오프라인비용 + 온라인비용) AS 총마케팅비
FROM marketing_info
GROUP BY DATE_FORMAT(날짜, '%b');

CREATE OR REPLACE VIEW 월별_매출_합계 AS
SELECT
	월,
	SUM(평균금액 * 수량) AS 매출합,
	SUM(순수익) AS 마진합
FROM 거래_순수익계산
GROUP BY 월;

CREATE OR REPLACE VIEW 마케팅비_매출_효율계산 AS
SELECT
	m.월, m.오프라인비용합계, m.온라인비용합계, m.총마케팅비,
	r.매출합, r.마진합,
	r.매출합 / m.총마케팅비 AS 매출ROAS,
	r.마진합 / m.총마케팅비 AS 마진ROAS
FROM 월별_마케팅비_합계 m
LEFT JOIN 월별_매출_합계 r ON m.월 = r.월;


-- =======================================================================================================
-- PART 2-1. 액션 임팩트 시뮬레이션 (검증 결과 -> 액션아이템 연결)
-- 2~8단계는 What(수익성)->Who(세그먼트)->Where(카테고리)->How(마케팅효율) 순으로 이어지는
-- '가설 검증'파트였고, 이 섹션은 그 검증 결과를 종합해 '그래서 어디서부터 손댈 것인가'를 판단하는
-- 별도 성격의 파트라 단계 번호를 붙이지 않음 (탐색 분석이 아니라 의사결정 시뮬레이션)
-- =======================================================================================================

-- '상품라인당 평균순수익을 저의존 세그먼트 수준까지 개선한다고 가정하면
-- 분석용 순수익이 얼마나 증가하는가'를 비교하는 단순 시나리오
-- 완전의존/고의존 중 총량 기준 개선 여지가 큰 세그먼트를 비교
-- 카테고리가 등장하지 않는 별개의 분석 - 4단계의 '쿠폰의존 세그먼트'만 재료로 사용하며,
-- 지금까지의 모든 발견(What-Who-Where-How)을 종합하여 '그래서 어디부터 손댈 것인가'로 이어지는
-- 마지막 단계이자 액션 아이템으로 넘어가는 다리 역할

-- 아래 '거래건당'은 상품라인당을 의미한다(고유 주문당 아님).
-- Tableau 호환을 위해 컬럼명은 유지하고, PPT·대시보드에서는 '상품라인당'으로 표기.
CREATE OR REPLACE VIEW 세그먼트별_거래건당마진 AS
SELECT
	세그먼트,
	SUM(총거래건수) AS 총거래건수,
	SUM(총순수익) AS 총순수익,
	SUM(총순수익) / SUM(총거래건수) AS 거래건당_평균순수익
FROM 고객_세그먼트
GROUP BY 세그먼트;

-- 저의존 세그먼트를 벤치마크 삼아, 완전의존/고의존을 그 수준까지 개선했을 때의 예상 증분
-- 결과 확인용 (Tableau CSV 추출은 PART 3의 (I) 사용)
SELECT
	a.세그먼트,
	a.거래건당_평균순수익,
    a.총거래건수,
    (b.거래건당_평균순수익 - a.거래건당_평균순수익) * a.총거래건수 AS 예상증분
FROM 세그먼트별_거래건당마진 a
CROSS JOIN (SELECT 거래건당_평균순수익 FROM 세그먼트별_거래건당마진 WHERE 세그먼트 = '저의존') b
WHERE a.세그먼트 IN ('완전의존','고의존');
-- 완전의존 37 / 고의존 11,469는 주문 수가 아니라 상품라인 수.
-- 본 결과는 저의존 세그먼트를 벤치마크로 둔 가정상 시나리오이며 캠페인의 실제 증분 이익이 아님.
-- 상품라인당 개선 여지는 완전의존이 더 크지만, 적용 가능한 상품라인 규모는 고의존이 훨씬 큼.
-- 메인 액션아이템 : 고의존 대상 할인 의존도 완화 CRM
-- 보조 액션아이템 : 완전의존은 규모가 작아 소규모·저비용 실험으로 반응 확인
-- 실제 캠페인 효과는 A/B 테스트 등 후속 실험으로 검증 필요


-- =======================================================================================================
-- PART 3. 최종 산출물 조회 (Tableau CSV 추출용)
-- =======================================================================================================

-- (A) 거래 단위 상세 - 카테고리/월별 마진 대시보드용 (02_거래별_순수익상세)
SELECT * FROM 거래_순수익계산;

-- (B) 고객별 쿠폰의존 세그먼트 - 세그먼트 비교 대시보드용 (04_고객_쿠폰의존세그먼트)
SELECT * FROM 고객_세그먼트;

-- (C) 쿠폰의존 세그먼트 x 카테고리 선호지수 - 세그먼트별 선호 카테고리 시각화용 (05_세그먼트_카테고리선호지수)
SELECT * FROM 세그먼트_지수
WHERE 거래건수 >= 10
ORDER BY 세그먼트, 선호지수 DESC;

-- 검증용: 필터 없는 전체 조합 (CSV 추출에는 사용하지 않음)
SELECT * FROM 세그먼트_지수;

-- (D) RFM 라이프사이클 세그먼트 x 쿠폰의존 세그먼트 교차 - CRM 타겟팅 대시보드용 (06_RFM_라이프사이클세그먼트 & 06_RFM_쿠폰의존_교차표)
SELECT * FROM RFM_라이프사이클;

SELECT 가입구분, RFM등급, 쿠폰의존세그먼트, COUNT(*) AS 고객수, AVG(M_순수익) AS 평균순수익
FROM RFM_라이프사이클
GROUP BY 가입구분, RFM등급, 쿠폰의존세그먼트
ORDER BY 가입구분, RFM등급, 쿠폰의존세그먼트;

-- (E) 카테고리 x 월 / 연간 수익성 (7-1) - 수익성 현황 대시보드용 (07_카테고리월별_수익성 & 07_카테고리연간_수익성)
SELECT * FROM 카테고리월별_수익성 ORDER BY 마진율 ASC;
SELECT * FROM 카테고리별_연간수익성 ORDER BY 마진율 ASC;

-- (F) RFM 라이프사이클 세그먼트 x 카테고리 마진갭 분석 (7-2) - 액션아이템 근거용 (07_RFM세그먼트_마진갭분석)
SELECT * FROM 라이프사이클_마진갭분석 ORDER BY 가입구분, RFM등급;

-- (G) 이탈위험 고객군 상품라인당 평균순수익 비교 - Slide 7 시각화용 (07_기존RFM낮음_상품라인당수익)
-- 이탈위험 고객 = 기존 가입(가입기간 12개월 초과) + RFM 등급 '낮음'. 실제 이탈 예측이 아닌 RFM 기준 분류
-- 이탈위험 고객(기존+낮음)과 기타 고객의 상품라인당 평균순수익을 비교하여 Slide 7 성과격차 시각화에 사용
SELECT
    CASE
        WHEN l.가입구분 = '기존' AND l.RFM등급 = '낮음'
            THEN '기존+낮음'
        ELSE '기타 고객'
    END AS 고객그룹,
    SUM(t.순수익) / COUNT(*) AS 상품라인당_평균순수익,
    COUNT(*) AS 상품라인수
FROM RFM_라이프사이클 l
LEFT JOIN 거래_순수익계산 t
    ON l.고객ID = t.고객ID
GROUP BY
    CASE
        WHEN l.가입구분 = '기존' AND l.RFM등급 = '낮음'
            THEN '기존+낮음'
        ELSE '기타 고객'
    END;

-- (G-2) 이탈위험 고객 vs 기타 고객 쿠폰 이용 패턴 - Slide 8 하단 비교용
-- Used비중 = Used 상품라인 수 / 전체 상품라인 수, 실효할인율 = 1 - 실질금액 합 / 할인 전 매출 합
-- 결과: Used비중 35.2% vs 33.8%, 실효할인율 7.06% vs 6.64%
SELECT
    CASE WHEN l.가입구분 = '기존' AND l.RFM등급 = '낮음'
         THEN '기존+낮음' ELSE '기타 고객' END AS 고객그룹,
    SUM(CASE WHEN t.쿠폰상태 = 'Used' THEN 1 ELSE 0 END) * 100.0 / COUNT(*) AS Used비중,
    (1 - SUM(t.실질금액) / SUM(t.평균금액 * t.수량)) * 100 AS 실효할인율
FROM RFM_라이프사이클 l
LEFT JOIN 거래_순수익계산 t ON l.고객ID = t.고객ID
GROUP BY 고객그룹;


-- (H) 마케팅비 대비 매출 효율 (8단계) - 마케팅 효율 대시보드용 (08_마케팅비_매출효율ROAS)
SELECT * 
FROM 마케팅비_매출_효율계산
ORDER BY 마진ROAS DESC;


-- (I) 쿠폰의존 세그먼트별 액션 기대효과 시뮬레이션 - 성과/기대효과 대시보드용 (09_액션임팩트_시뮬레이션)
SELECT
	a.세그먼트, a.거래건당_평균순수익, a.총거래건수,
    (b.거래건당_평균순수익 - a.거래건당_평균순수익) * a.총거래건수 AS 예상증분
FROM 세그먼트별_거래건당마진 a
CROSS JOIN (SELECT 거래건당_평균순수익 FROM 세그먼트별_거래건당마진 WHERE 세그먼트 = '저의존') b
WHERE a.세그먼트 IN ('완전의존','고의존');