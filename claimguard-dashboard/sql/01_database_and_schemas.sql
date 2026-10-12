-- ============================================================
-- ClaimGuard AI — Deployment Script 1: Database and Schemas
-- Run this first. Creates the database and 4 schemas.
-- ============================================================

CREATE DATABASE IF NOT EXISTS CLAIMGUARD
    COMMENT = 'ClaimGuard AI - Agentic RAG for Healthcare Insurance Claim Denial Prevention';

CREATE SCHEMA IF NOT EXISTS CLAIMGUARD.RAW
    COMMENT = 'Landing zone for incoming claims and policy files';

CREATE SCHEMA IF NOT EXISTS CLAIMGUARD.CORE
    COMMENT = 'Normalized patient, claim, and clinical data - views over marketplace data';

CREATE SCHEMA IF NOT EXISTS CLAIMGUARD.RAG
    COMMENT = 'Policy documents, chunks, and Cortex Search service for RAG';

CREATE SCHEMA IF NOT EXISTS CLAIMGUARD.APP
    COMMENT = 'Review queue, findings, reviewer actions, and pipeline tracking';
