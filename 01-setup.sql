-- 01_setup.sql
-- One-time setup for the NYC 311 pipeline.
-- Creates the nyc311 database and the raw schema that load.py writes to.
-- Run with: psql -U postgres -f 01_setup.sql


CREATE DATABASE nyc311;

-- Switch into the new database so the schema is created in the right place.
\c nyc311

-- Raw layer: data exactly as received from the source APIs.
CREATE SCHEMA raw;