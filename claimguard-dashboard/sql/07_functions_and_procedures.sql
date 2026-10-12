-- ============================================================
-- ClaimGuard AI — Deployment Script 7: Functions and Procedures
-- Prerequisites: Scripts 01, 02, 05
-- ============================================================

-- Deterministic rules engine (8 SQL checks)
CREATE OR REPLACE FUNCTION CLAIMGUARD.APP.CHECK_CLAIM_REQUIREMENTS(CLAIM_ID_INPUT NUMBER)
RETURNS TABLE (REQUIREMENT_CODE VARCHAR, STATUS VARCHAR, FINDING_TYPE VARCHAR, FINDING VARCHAR, CITATION VARCHAR, IS_DETERMINISTIC BOOLEAN)
LANGUAGE SQL
COMMENT = 'Deterministic rules engine: checks 8 SQL-testable policy requirements for a claim'
AS
$$
    SELECT 'REQ-001', CASE WHEN cnt > 0 THEN 'PASS' ELSE 'ISSUE_FOUND' END, 'CLINICAL',
           CASE WHEN cnt > 0 THEN 'Blood gas or oximetry result found (' || cnt || ' readings).'
                ELSE 'No arterial blood gas or pulse oximetry result found for this encounter.' END,
           'NCD 240.2, Section: Qualifying Blood Gas Criteria', TRUE
    FROM (SELECT COUNT(*) AS cnt FROM CLAIMGUARD.CORE.OBSERVATIONS o
          JOIN CLAIMGUARD.CORE.CLAIMS c ON o.ENCOUNTER_ID = c.ENCOUNTER_ID
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT
          AND (o.OBSERVATION_DESCRIPTION ILIKE '%oxygen%saturation%'
               OR o.OBSERVATION_DESCRIPTION ILIKE '%blood gas%'
               OR o.OBSERVATION_CODE IN ('2708-6', '59408-5', '2713-6')))
    UNION ALL
    SELECT 'REQ-002',
           CASE WHEN o2_val IS NULL THEN 'INSUFFICIENT_INFORMATION' WHEN o2_val <= 88 THEN 'PASS'
                WHEN o2_val = 89 THEN 'NEEDS_VERIFICATION' ELSE 'ISSUE_FOUND' END, 'CLINICAL',
           CASE WHEN o2_val IS NULL THEN 'No numeric O2 saturation value found to evaluate against threshold.'
                WHEN o2_val <= 88 THEN 'O2 saturation is ' || o2_val || '% — meets Group I criteria (≤88%).'
                WHEN o2_val = 89 THEN 'O2 saturation is 89% — qualifies only with secondary diagnosis (Group II).'
                ELSE 'O2 saturation is ' || o2_val || '% — above qualifying threshold.' END,
           'NCD 240.2, Section: Qualifying Blood Gas Criteria - Group I and Group II', TRUE
    FROM (SELECT MIN(TRY_TO_NUMBER(o.VALUE)) AS o2_val FROM CLAIMGUARD.CORE.OBSERVATIONS o
          JOIN CLAIMGUARD.CORE.CLAIMS c ON o.ENCOUNTER_ID = c.ENCOUNTER_ID
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT
          AND (o.OBSERVATION_DESCRIPTION ILIKE '%oxygen%saturation%' OR o.OBSERVATION_CODE IN ('59408-5', '2713-6'))
          AND TRY_TO_NUMBER(o.VALUE) IS NOT NULL)
    UNION ALL
    SELECT 'REQ-008', CASE WHEN cnt > 0 THEN 'PASS' ELSE 'ISSUE_FOUND' END, 'CLINICAL',
           CASE WHEN cnt > 0 THEN 'Qualifying respiratory diagnosis documented (' || cnt || ' conditions).'
                ELSE 'No qualifying respiratory diagnosis found for this encounter.' END,
           'LCD L33797, Section: Qualifying ICD-10 Diagnosis Codes', TRUE
    FROM (SELECT COUNT(*) AS cnt FROM CLAIMGUARD.CORE.DIAGNOSES d
          JOIN CLAIMGUARD.CORE.CLAIMS c ON d.ENCOUNTER_ID = c.ENCOUNTER_ID
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT
          AND d.DIAGNOSIS_DESCRIPTION ILIKE ANY ('%respiratory%','%copd%','%pulmonary%','%lung%','%emphysema%','%hypoxia%','%asthma%'))
    UNION ALL
    SELECT 'REQ-009', CASE WHEN cnt > 0 THEN 'PASS' ELSE 'NEEDS_VERIFICATION' END, 'ADMINISTRATIVE',
           CASE WHEN cnt > 0 THEN 'Valid home oxygen HCPCS procedure code found.'
                ELSE 'No home oxygen HCPCS code found. Verify correct coding.' END,
           'NCD 240.2, Section: HCPCS Codes for Home Oxygen Equipment', TRUE
    FROM (SELECT COUNT(*) AS cnt FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS_TX tx
          JOIN CLAIMGUARD.CORE.CLAIMS c ON tx.CLAIM_ID = c.CLAIM_ID
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT AND tx.PROCEDURECODE IN (386341005, 243147009, 371907003, 57485005))
    UNION ALL
    SELECT 'REQ-011', CASE WHEN cnt >= 3 THEN 'PASS' ELSE 'ISSUE_FOUND' END, 'DOCUMENTATION',
           CASE WHEN cnt >= 3 THEN cnt || ' clinical observations documented.'
                ELSE 'Only ' || cnt || ' clinical observations on file. Insufficient documentation.' END,
           'LCD L33797, Section: Required Documentation', TRUE
    FROM (SELECT COUNT(*) AS cnt FROM CLAIMGUARD.CORE.OBSERVATIONS o
          JOIN CLAIMGUARD.CORE.CLAIMS c ON o.ENCOUNTER_ID = c.ENCOUNTER_ID WHERE c.CLAIM_ID = CLAIM_ID_INPUT)
    UNION ALL
    SELECT 'REQ-013',
           CASE WHEN obs_date IS NULL THEN 'INSUFFICIENT_INFORMATION'
                WHEN DATEDIFF('day', obs_date, svc_date) BETWEEN 0 AND 30 THEN 'PASS'
                WHEN DATEDIFF('day', obs_date, svc_date) < 0 THEN 'PASS'
                ELSE 'ISSUE_FOUND' END, 'CLINICAL',
           CASE WHEN obs_date IS NULL THEN 'No O2/blood gas observation date found to verify timing.'
                WHEN DATEDIFF('day', obs_date, svc_date) BETWEEN 0 AND 30 THEN 'Blood gas test within 30-day window.'
                WHEN DATEDIFF('day', obs_date, svc_date) < 0 THEN 'Blood gas test performed after service date.'
                ELSE 'Blood gas test ' || DATEDIFF('day', obs_date, svc_date) || ' days before service — exceeds 30-day limit.' END,
           'PA A52510, Section: Common Denial Reasons - Test timing', TRUE
    FROM (SELECT MAX(o.OBSERVATION_DATE)::DATE AS obs_date, MAX(c.SERVICEDATE)::DATE AS svc_date
          FROM CLAIMGUARD.CORE.CLAIMS c
          LEFT JOIN CLAIMGUARD.CORE.OBSERVATIONS o ON o.ENCOUNTER_ID = c.ENCOUNTER_ID
              AND (o.OBSERVATION_DESCRIPTION ILIKE '%oxygen%saturation%' OR o.OBSERVATION_CODE IN ('2708-6','59408-5','2713-6'))
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT)
    UNION ALL
    SELECT 'REQ-015', CASE WHEN cnt > 0 THEN 'PASS' ELSE 'NEEDS_VERIFICATION' END, 'ADMINISTRATIVE',
           CASE WHEN cnt > 0 THEN 'KX modifier found on ' || cnt || ' claim line(s).'
                ELSE 'No KX modifier found. Required to indicate medical necessity.' END,
           'PA A52510, Section: Billing Guidelines and Modifiers', TRUE
    FROM (SELECT COUNT(*) AS cnt FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.CLAIMS_TX tx
          JOIN CLAIMGUARD.CORE.CLAIMS c ON tx.CLAIM_ID = c.CLAIM_ID
          WHERE c.CLAIM_ID = CLAIM_ID_INPUT AND (tx.MODIFIER1 ILIKE '%KX%' OR tx.MODIFIER2 ILIKE '%KX%'))
    UNION ALL
    SELECT 'REQ-TREAT', CASE WHEN (dev_cnt + med_cnt) > 0 THEN 'PASS' ELSE 'NEEDS_VERIFICATION' END, 'CLINICAL',
           CASE WHEN (dev_cnt + med_cnt) > 0 THEN 'Treatment documented: ' || dev_cnt || ' device(s), ' || med_cnt || ' medication(s).'
                ELSE 'No devices or medications documented. Verify treatment is recorded.' END,
           'LCD L33797, Section: Required Documentation', TRUE
    FROM (SELECT
            (SELECT COUNT(*) FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.DEVICES d
             JOIN CLAIMGUARD.CORE.CLAIMS c ON d.ENCOUNTER_ID = c.ENCOUNTER_ID WHERE c.CLAIM_ID = CLAIM_ID_INPUT) AS dev_cnt,
            (SELECT COUNT(*) FROM SYNTHETIC_HEALTHCARE_DATA_CLINICAL_AND_CLAIMS.SILVER.MEDICATIONS m
             JOIN CLAIMGUARD.CORE.CLAIMS c ON m.ENCOUNTER_ID = c.ENCOUNTER_ID WHERE c.CLAIM_ID = CLAIM_ID_INPUT) AS med_cnt)
$$;

-- LLM-based clinical note checker (6 checks)
-- See CHECK_CLAIM_LLM procedure created separately (Python stored procedure)
-- Recreate with: The procedure code is in the repository but must be created via
-- Snowsight or snowsql due to Python handler requirements.

-- Evaluation runner
CREATE OR REPLACE PROCEDURE CLAIMGUARD.APP.RUN_EVALUATION(EVAL_ID_INPUT NUMBER)
RETURNS VARCHAR
LANGUAGE PYTHON
RUNTIME_VERSION = '3.11'
PACKAGES = ('snowflake-snowpark-python')
HANDLER = 'run_eval'
AS
$$
def run_eval(session, eval_id_input):
    gold_claims = session.sql("SELECT DISTINCT CLAIM_ID FROM CLAIMGUARD.APP.GOLD_SET").collect()
    total = 0
    for row in gold_claims:
        claim_id = row['CLAIM_ID']
        results = session.sql(f"SELECT REQUIREMENT_CODE, STATUS, FINDING, CITATION FROM TABLE(CLAIMGUARD.APP.CHECK_CLAIM_REQUIREMENTS({claim_id}))").collect()
        expected = session.sql(f"SELECT REQUIREMENT_CODE, EXPECTED_STATUS FROM CLAIMGUARD.APP.GOLD_SET WHERE CLAIM_ID = {claim_id}").collect()
        expected_map = {e['REQUIREMENT_CODE']: e['EXPECTED_STATUS'] for e in expected}
        for r in results:
            req_code = r['REQUIREMENT_CODE']
            if req_code in expected_map:
                exp_status = expected_map[req_code]
                actual_status = r['STATUS']
                is_correct = (exp_status == actual_status)
                session.sql(f"INSERT INTO CLAIMGUARD.APP.EVALUATION_RESULTS (EVAL_ID, CLAIM_ID, REQUIREMENT_CODE, EXPECTED_STATUS, ACTUAL_STATUS, IS_CORRECT, ACTUAL_FINDING, ACTUAL_CITATION) VALUES ({eval_id_input}, {claim_id}, '{req_code}', '{exp_status}', '{actual_status}', {str(is_correct).upper()}, '{r['FINDING'].replace(chr(39), chr(39)+chr(39))}', '{r['CITATION'].replace(chr(39), chr(39)+chr(39))}')").collect()
                total += 1
    metrics = session.sql(f"SELECT SUM(CASE WHEN EXPECTED_STATUS='ISSUE_FOUND' AND ACTUAL_STATUS='ISSUE_FOUND' THEN 1 ELSE 0 END) AS TP, SUM(CASE WHEN EXPECTED_STATUS='PASS' AND ACTUAL_STATUS='ISSUE_FOUND' THEN 1 ELSE 0 END) AS FP, SUM(CASE WHEN EXPECTED_STATUS='PASS' AND ACTUAL_STATUS='PASS' THEN 1 ELSE 0 END) AS TN, SUM(CASE WHEN EXPECTED_STATUS='ISSUE_FOUND' AND ACTUAL_STATUS='PASS' THEN 1 ELSE 0 END) AS FN, COUNT(*) AS TOTAL, SUM(CASE WHEN ACTUAL_CITATION IS NOT NULL THEN 1 ELSE 0 END) AS CITED FROM CLAIMGUARD.APP.EVALUATION_RESULTS WHERE EVAL_ID = {eval_id_input}").collect()[0]
    tp, fp, tn, fn = metrics['TP'] or 0, metrics['FP'] or 0, metrics['TN'] or 0, metrics['FN'] or 0
    cited, total_r = metrics['CITED'] or 0, metrics['TOTAL'] or 0
    precision = tp/(tp+fp) if (tp+fp)>0 else 0
    recall = tp/(tp+fn) if (tp+fn)>0 else 0
    f1 = 2*precision*recall/(precision+recall) if (precision+recall)>0 else 0
    cit_acc = cited/total_r if total_r>0 else 0
    session.sql(f"UPDATE CLAIMGUARD.APP.EVALUATION_RUNS SET TRUE_POSITIVES={tp}, FALSE_POSITIVES={fp}, TRUE_NEGATIVES={tn}, FALSE_NEGATIVES={fn}, PRECISION_SCORE={precision:.4f}, RECALL_SCORE={recall:.4f}, F1_SCORE={f1:.4f}, CITATION_CORRECT={cited}, CITATION_TOTAL={total_r}, CITATION_ACCURACY={cit_acc:.4f}, TOTAL_CASES={total_r} WHERE EVAL_ID={eval_id_input}").collect()
    return f"Evaluation complete: {total_r} cases, Precision={precision:.2%}, Recall={recall:.2%}, F1={f1:.2%}, Citation={cit_acc:.2%}"
$$;
