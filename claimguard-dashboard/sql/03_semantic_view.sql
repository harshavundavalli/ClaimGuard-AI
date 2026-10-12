-- ============================================================
-- ClaimGuard AI — Deployment Script 3: Semantic View
-- Prerequisites: Script 02 (CORE views)
-- ============================================================

CREATE OR REPLACE SEMANTIC VIEW CLAIMGUARD.CORE.CLAIM_REVIEW_VIEW
  TABLES (
    patients AS CLAIMGUARD.CORE.PATIENTS PRIMARY KEY (PATIENT_ID)
      COMMENT = 'One row per patient with demographics',
    encounters AS CLAIMGUARD.CORE.ENCOUNTERS PRIMARY KEY (ENCOUNTER_ID)
      COMMENT = 'One row per healthcare encounter/visit',
    claims AS CLAIMGUARD.CORE.CLAIMS PRIMARY KEY (CLAIM_ID)
      COMMENT = 'One row per insurance claim submitted for an encounter',
    diagnoses AS CLAIMGUARD.CORE.DIAGNOSES PRIMARY KEY (DIAGNOSIS_ID)
      COMMENT = 'One row per diagnosed condition for a patient encounter',
    observations AS CLAIMGUARD.CORE.OBSERVATIONS PRIMARY KEY (OBSERVATION_ID)
      COMMENT = 'Clinical observations including vitals and lab results like oxygen saturation'
  )
  RELATIONSHIPS (
    encounters_to_patients AS encounters (PATIENT_ID) REFERENCES patients,
    claims_to_patients AS claims (PATIENT_ID) REFERENCES patients,
    claims_to_encounters AS claims (ENCOUNTER_ID) REFERENCES encounters,
    diagnoses_to_patients AS diagnoses (PATIENT_ID) REFERENCES patients,
    diagnoses_to_encounters AS diagnoses (ENCOUNTER_ID) REFERENCES encounters,
    observations_to_patients AS observations (PATIENT_ID) REFERENCES patients,
    observations_to_encounters AS observations (ENCOUNTER_ID) REFERENCES encounters
  )
  DIMENSIONS (
    patients.patient_name AS FULL_NAME WITH SYNONYMS = ('patient name', 'name', 'beneficiary') COMMENT = 'Full name of the patient',
    patients.patient_state AS STATE WITH SYNONYMS = ('state', 'location') COMMENT = 'Patient state of residence',
    patients.patient_gender AS GENDER COMMENT = 'Patient gender M or F',
    patients.patient_birthdate AS BIRTHDATE COMMENT = 'Patient date of birth',
    encounters.encounter_class AS ENCOUNTERCLASS WITH SYNONYMS = ('visit type', 'encounter type', 'setting') COMMENT = 'Type: ambulatory, emergency, inpatient, wellness, urgentcare',
    encounters.encounter_description AS ENCOUNTER_DESCRIPTION COMMENT = 'Description of the encounter type',
    encounters.encounter_start_date AS ENCOUNTER_START COMMENT = 'When the encounter started',
    claims.claim_service_date AS SERVICEDATE WITH SYNONYMS = ('date of service', 'service date', 'DOS') COMMENT = 'Date the claimed service was provided',
    claims.claim_primary_status AS PRIMARY_STATUS WITH SYNONYMS = ('claim status', 'status') COMMENT = 'Primary payer claim status: BILLED or CLOSED',
    claims.claim_diagnosis1 AS DIAGNOSIS1 WITH SYNONYMS = ('primary diagnosis', 'diagnosis code') COMMENT = 'Primary SNOMED-CT diagnosis code on the claim',
    diagnoses.diagnosis_description AS DIAGNOSIS_DESCRIPTION WITH SYNONYMS = ('condition', 'diagnosis name', 'disease') COMMENT = 'Human-readable description of the diagnosed condition',
    diagnoses.diagnosis_code AS DIAGNOSIS_CODE WITH SYNONYMS = ('SNOMED code', 'condition code') COMMENT = 'SNOMED-CT code for the diagnosed condition',
    diagnoses.diagnosis_onset AS ONSET_DATE COMMENT = 'Date the condition was first diagnosed',
    observations.obs_description AS OBSERVATION_DESCRIPTION WITH SYNONYMS = ('lab test', 'vital sign', 'measurement', 'oxygen saturation', 'O2 sat', 'SpO2', 'blood gas', 'PaO2') COMMENT = 'Description of the clinical observation or lab test',
    observations.obs_code AS OBSERVATION_CODE WITH SYNONYMS = ('LOINC code', 'lab code') COMMENT = 'LOINC code identifying the observation type',
    observations.obs_value AS VALUE WITH SYNONYMS = ('result', 'reading', 'test result') COMMENT = 'Recorded value of the observation',
    observations.obs_units AS UNITS COMMENT = 'Units of measurement',
    observations.obs_date AS OBSERVATION_DATE COMMENT = 'Date and time the observation was recorded'
  )
  METRICS (
    encounters.total_cost AS SUM(TOTAL_CLAIM_COST) WITH SYNONYMS = ('claim amount', 'encounter cost') COMMENT = 'Total cost of encounters including all line items',
    encounters.covered_amount AS SUM(PAYER_COVERAGE) WITH SYNONYMS = ('insurance paid', 'reimbursement') COMMENT = 'Amount covered by the insurance payer'
  );
