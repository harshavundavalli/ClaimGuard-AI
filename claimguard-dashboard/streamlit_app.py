import os
import streamlit as st
import json
from datetime import datetime

st.set_page_config(page_title="ClaimGuard AI", page_icon="🛡️", layout="wide")

conn = st.connection("snowflake", ttl=os.getenv("SNOWFLAKE_CONNECTION_TTL"))


@st.cache_data(ttl=60)
def get_queue_stats():
    return conn.query("""
        SELECT
            COUNT(*) AS total,
            SUM(CASE WHEN QUEUE_STATUS = 'PENDING' THEN 1 ELSE 0 END) AS pending,
            SUM(CASE WHEN QUEUE_STATUS = 'COMPLETED' THEN 1 ELSE 0 END) AS completed,
            SUM(CASE WHEN QUEUE_STATUS = 'FAILED' THEN 1 ELSE 0 END) AS failed
        FROM CLAIMGUARD.APP.REVIEW_QUEUE
    """)


@st.cache_data(ttl=60)
def get_review_queue():
    return conn.query("""
        SELECT
            q.QUEUE_ID,
            q.CLAIM_ID,
            q.PATIENT_ID,
            q.QUEUE_STATUS,
            q.PRIORITY,
            q.QUEUED_AT,
            q.RETRY_COUNT,
            p.FULL_NAME AS PATIENT_NAME,
            p.STATE AS PATIENT_STATE
        FROM CLAIMGUARD.APP.REVIEW_QUEUE q
        LEFT JOIN CLAIMGUARD.CORE.PATIENTS p ON q.PATIENT_ID = p.PATIENT_ID
        ORDER BY q.PRIORITY ASC, q.QUEUED_AT ASC
    """)


@st.cache_data(ttl=300)
def get_claim_detail(claim_id):
    return conn.query(
        "SELECT * FROM CLAIMGUARD.CORE.CLAIMS WHERE CLAIM_ID = :1",
        params=[int(claim_id)]
    )


@st.cache_data(ttl=300)
def get_claim_diagnoses(claim_id):
    return conn.query("""
        SELECT d.DIAGNOSIS_CODE, d.DIAGNOSIS_DESCRIPTION, d.ONSET_DATE
        FROM CLAIMGUARD.CORE.DIAGNOSES d
        JOIN CLAIMGUARD.CORE.CLAIMS c ON d.ENCOUNTER_ID = c.ENCOUNTER_ID
        WHERE c.CLAIM_ID = :1
    """, params=[int(claim_id)])


@st.cache_data(ttl=300)
def get_claim_observations(claim_id):
    return conn.query("""
        SELECT o.OBSERVATION_DESCRIPTION, o.VALUE, o.UNITS, o.OBSERVATION_DATE
        FROM CLAIMGUARD.CORE.OBSERVATIONS o
        JOIN CLAIMGUARD.CORE.CLAIMS c ON o.ENCOUNTER_ID = c.ENCOUNTER_ID
        WHERE c.CLAIM_ID = :1
        ORDER BY o.OBSERVATION_DATE DESC
        LIMIT 50
    """, params=[int(claim_id)])


@st.cache_data(ttl=300)
def run_rules_check(claim_id):
    return conn.query(
        "SELECT * FROM TABLE(CLAIMGUARD.APP.CHECK_CLAIM_REQUIREMENTS(:1))",
        params=[int(claim_id)]
    )


@st.cache_data(ttl=300)
def get_policy_requirements():
    return conn.query("""
        SELECT REQUIREMENT_CODE, REQUIREMENT_TEXT, REQUIREMENT_TYPE, IS_TESTABLE
        FROM CLAIMGUARD.RAG.POLICY_REQUIREMENTS
        ORDER BY REQUIREMENT_CODE
    """)


@st.cache_data(ttl=300)
def get_clinical_notes(claim_id):
    return conn.query(
        "SELECT NOTE_TYPE, NOTE_DATE, NOTE_TEXT FROM CLAIMGUARD.CORE.CLINICAL_NOTES WHERE CLAIM_ID = :1 ORDER BY NOTE_TYPE",
        params=[int(claim_id)]
    )


def run_llm_checks(claim_id):
    result = conn.query(
        "CALL CLAIMGUARD.APP.CHECK_CLAIM_LLM(:1)",
        params=[int(claim_id)]
    )
    if not result.empty:
        import json
        raw = result.iloc[0, 0]
        parsed = json.loads(raw) if isinstance(raw, str) else raw
        import pandas as pd
        return pd.DataFrame(parsed)
    return None


@st.cache_data(ttl=300)
def get_review_findings(claim_id):
    return conn.query(
        "SELECT * FROM CLAIMGUARD.APP.REVIEW_FINDINGS WHERE CLAIM_ID = :1 ORDER BY CREATED_AT DESC",
        params=[int(claim_id)]
    )


@st.cache_data(ttl=300)
def get_review_actions(review_id):
    return conn.query(
        "SELECT * FROM CLAIMGUARD.APP.REVIEW_ACTIONS WHERE REVIEW_ID = :1 ORDER BY CREATED_AT DESC",
        params=[int(review_id)]
    )


def save_review_action(review_id, finding_id, action_type, notes, reviewer):
    conn.query("""
        INSERT INTO CLAIMGUARD.APP.REVIEW_ACTIONS
            (REVIEW_ID, FINDING_ID, ACTION_TYPE, REVIEWER_USER, ACTION_NOTES)
        VALUES (:1, :2, :3, :4, :5)
    """, params=[int(review_id) if review_id else 0,
                 int(finding_id) if finding_id else None,
                 action_type, reviewer, notes])


# ── Sidebar ──
with st.sidebar:
    st.title("ClaimGuard AI")
    st.caption("Pre-submission Review Assistant")
    st.divider()

    page = st.radio(
        "Navigation",
        ["Review Queue", "Claim Review", "Policy Reference", "Pipeline Status"],
        label_visibility="collapsed"
    )

    st.divider()
    if st.button("Refresh Data"):
        get_queue_stats.clear()
        get_review_queue.clear()
        st.rerun()


# ── Page: Review Queue ──
if page == "Review Queue":
    st.header("Review Queue")

    stats = get_queue_stats()
    if not stats.empty:
        row = stats.iloc[0]
        with st.container(horizontal=True):
            st.metric("Total Claims", int(row["TOTAL"]), border=True)
            st.metric("Pending Review", int(row["PENDING"]), border=True)
            st.metric("Completed", int(row["COMPLETED"]), border=True)
            st.metric("Failed", int(row["FAILED"]), border=True)

    st.subheader("Claims Awaiting Review")
    queue_df = get_review_queue()

    if not queue_df.empty:
        status_filter = st.multiselect(
            "Filter by status",
            queue_df["QUEUE_STATUS"].unique().tolist(),
            default=["PENDING"]
        )
        filtered = queue_df[queue_df["QUEUE_STATUS"].isin(status_filter)] if status_filter else queue_df

        st.dataframe(
            filtered,
            hide_index=True,
            use_container_width=True,
            column_config={
                "CLAIM_ID": st.column_config.NumberColumn("Claim ID", format="%d"),
                "PATIENT_NAME": "Patient",
                "PATIENT_STATE": "State",
                "QUEUE_STATUS": "Status",
                "PRIORITY": st.column_config.NumberColumn("Priority", format="%d"),
                "QUEUED_AT": st.column_config.DatetimeColumn("Queued At", format="YYYY-MM-DD HH:mm"),
                "RETRY_COUNT": st.column_config.NumberColumn("Retries", format="%d"),
            }
        )

        st.info("To review a claim, copy its Claim ID and go to **Claim Review** in the sidebar.")
    else:
        st.info("No claims in the review queue.")


# ── Page: Claim Review ──
elif page == "Claim Review":
    st.header("Claim Review")

    claim_id = st.text_input("Enter Claim ID to review", placeholder="e.g. 177116435")

    if claim_id:
        claim_id = int(claim_id)

        # Claim details
        claim_df = get_claim_detail(claim_id)
        if claim_df.empty:
            st.error(f"Claim {claim_id} not found.")
        else:
            claim = claim_df.iloc[0]

            col1, col2 = st.columns(2)
            with col1:
                with st.container(border=True):
                    st.subheader("Claim Information")
                    st.markdown(f"""
                    - **Claim ID:** {claim_id}
                    - **Patient ID:** {claim['PATIENT_ID']}
                    - **Encounter ID:** {claim['ENCOUNTER_ID']}
                    - **Service Date:** {claim['SERVICEDATE']}
                    - **Status:** {claim['PRIMARY_STATUS']}
                    - **Primary Diagnosis Code:** {claim['DIAGNOSIS1']}
                    """)

            with col2:
                with st.container(border=True):
                    st.subheader("Diagnoses on File")
                    dx_df = get_claim_diagnoses(claim_id)
                    if not dx_df.empty:
                        st.dataframe(dx_df, hide_index=True, use_container_width=True)
                    else:
                        st.warning("No diagnoses found for this encounter.")

            # Clinical observations
            with st.container(border=True):
                st.subheader("Clinical Observations")
                obs_df = get_claim_observations(claim_id)
                if not obs_df.empty:
                    st.dataframe(obs_df, hide_index=True, use_container_width=True)
                else:
                    st.warning("No clinical observations found for this encounter.")

            st.divider()

            # Rules engine check
            st.subheader("Deterministic Requirements Check")
            with st.spinner("Running rules engine..."):
                rules_df = run_rules_check(claim_id)

            if not rules_df.empty:
                for _, finding in rules_df.iterrows():
                    status = finding["STATUS"]
                    if status == "PASS":
                        icon = "✅"
                    elif status == "ISSUE_FOUND":
                        icon = "❌"
                    elif status == "NEEDS_VERIFICATION":
                        icon = "⚠️"
                    else:
                        icon = "❓"

                    with st.container(border=True):
                        st.markdown(f"### {icon} {finding['REQUIREMENT_CODE']} — {status}")
                        st.markdown(f"**Type:** {finding['FINDING_TYPE']}")
                        st.markdown(f"**Finding:** {finding['FINDING']}")
                        st.markdown(f"**Citation:** _{finding['CITATION']}_")
            else:
                st.info("No rules check results available.")

            # Clinical notes
            with st.container(border=True):
                st.subheader("Clinical Notes")
                notes_df = get_clinical_notes(claim_id)
                if not notes_df.empty:
                    for _, note in notes_df.iterrows():
                        with st.expander(f"{note['NOTE_TYPE']} — {note['NOTE_DATE']}"):
                            st.markdown(note["NOTE_TEXT"])
                else:
                    st.warning("No clinical notes on file for this claim.")

            st.divider()

            # LLM-based checks
            st.subheader("LLM-Based Requirements Check")
            st.caption("These checks use AI to interpret clinical notes — results are non-deterministic and require human verification.")

            if notes_df is not None and not notes_df.empty:
                if st.button("Run LLM Checks (uses AI credits)"):
                    with st.spinner("Analyzing clinical notes with AI... this may take 15-30 seconds."):
                        llm_df = run_llm_checks(claim_id)

                    if llm_df is not None and not llm_df.empty:
                        for _, finding in llm_df.iterrows():
                            status = finding.get("status", "UNKNOWN")
                            if status == "PASS":
                                icon = "✅"
                            elif status == "ISSUE_FOUND":
                                icon = "❌"
                            elif status == "NEEDS_VERIFICATION":
                                icon = "⚠️"
                            else:
                                icon = "❓"

                            with st.container(border=True):
                                st.markdown(f"### {icon} {finding['requirement_code']} — {status}")
                                st.markdown(f"**Type:** {finding['finding_type']}")
                                st.markdown(f"**Finding:** {finding['finding']}")
                                st.markdown(f"**Citation:** _{finding['citation']}_")
                                st.caption("Non-deterministic — LLM interpretation of clinical notes")
                    else:
                        st.error("LLM evaluation returned no results.")
            else:
                st.info("No clinical notes available — LLM checks require clinical notes to evaluate.")

            st.divider()

            # Reviewer action
            st.subheader("Reviewer Action")
            with st.form("review_action_form"):
                action = st.selectbox("Action", ["ACCEPT", "REJECT", "REQUEST_MORE_INFO", "OVERRIDE", "ESCALATE"])
                notes = st.text_area("Notes", placeholder="Explain your decision...")
                submitted = st.form_submit_button("Submit Review Action")

                if submitted:
                    save_review_action(
                        review_id=0,
                        finding_id=None,
                        action_type=action,
                        notes=notes,
                        reviewer=conn.query("SELECT CURRENT_USER()").iloc[0, 0]
                    )
                    st.success(f"Action '{action}' recorded for claim {claim_id}.")


# ── Page: Policy Reference ──
elif page == "Policy Reference":
    st.header("Policy Reference")
    st.caption("NCD 240.2, LCD L33797, and PA A52510 requirements for home oxygen coverage")

    reqs_df = get_policy_requirements()
    if not reqs_df.empty:
        type_filter = st.multiselect(
            "Filter by type",
            reqs_df["REQUIREMENT_TYPE"].unique().tolist(),
            default=reqs_df["REQUIREMENT_TYPE"].unique().tolist()
        )
        filtered_reqs = reqs_df[reqs_df["REQUIREMENT_TYPE"].isin(type_filter)] if type_filter else reqs_df

        for _, req in filtered_reqs.iterrows():
            testable = "SQL-testable" if req["IS_TESTABLE"] else "Requires human/LLM review"
            with st.container(border=True):
                st.markdown(f"**{req['REQUIREMENT_CODE']}** ({req['REQUIREMENT_TYPE']})")
                st.markdown(req["REQUIREMENT_TEXT"])
                st.caption(testable)
    else:
        st.info("No policy requirements loaded.")


# ── Page: Pipeline Status ──
elif page == "Pipeline Status":
    st.header("Pipeline Status")

    col1, col2 = st.columns(2)

    with col1:
        with st.container(border=True):
            st.subheader("Stream Status")
            stream_df = conn.query("SHOW STREAMS IN SCHEMA CLAIMGUARD.RAW")
            if not stream_df.empty:
                for _, s in stream_df.iterrows():
                    st.markdown(f"**{s['name']}**")
                    st.markdown(f"- Source: `{s['table_name']}`")
                    st.markdown(f"- Stale: {s['stale']}")
            else:
                st.info("No streams found.")

    with col2:
        with st.container(border=True):
            st.subheader("Task Status")
            task_df = conn.query("SHOW TASKS IN SCHEMA CLAIMGUARD.APP")
            if not task_df.empty:
                for _, t in task_df.iterrows():
                    st.markdown(f"**{t['name']}**")
                    st.markdown(f"- State: {t['state']}")
                    st.markdown(f"- Schedule: {t['schedule']}")
                    st.markdown(f"- Warehouse: {t['warehouse']}")
            else:
                st.info("No tasks found.")

    with st.container(border=True):
        st.subheader("Recent Pipeline Runs")
        runs_df = conn.query("""
            SELECT RUN_ID, RUN_TYPE, RUN_STATUS, CLAIMS_PROCESSED, CLAIMS_FAILED, STARTED_AT, COMPLETED_AT
            FROM CLAIMGUARD.APP.PIPELINE_RUNS
            ORDER BY STARTED_AT DESC
            LIMIT 20
        """)
        if not runs_df.empty:
            st.dataframe(runs_df, hide_index=True, use_container_width=True)
        else:
            st.info("No pipeline runs recorded yet.")

    with st.container(border=True):
        st.subheader("Cortex Search Service")
        css_df = conn.query("SHOW CORTEX SEARCH SERVICES IN SCHEMA CLAIMGUARD.RAG")
        if not css_df.empty:
            for _, svc in css_df.iterrows():
                st.markdown(f"**{svc['name']}**")
                st.markdown(f"- Created: {svc['created_on']}")
        else:
            st.info("No search services found.")
