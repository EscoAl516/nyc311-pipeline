-- 01_setup.sql
-- One-time setup for the NYC 311 pipeline.
-- Creates the nyc311 database and the raw schema that load.py writes to.
-- Run with: psql -U postgres -f 01_setup.sql


CREATE DATABASE nyc311;

-- Switch into the new database so the schema is created in the right place.
\c nyc311

-- Raw layer: data exactly as received from the source APIs.
CREATE SCHEMA raw;

CREATE TABLE raw.service_requests (
	unique_key text NOT NULL,
	created_date text NULL,
	closed_date text NULL,
	agency text NULL,
	agency_name text NULL,
	complaint_type text NULL,
	"descriptor" text NULL,
	incident_zip text NULL,
	incident_address text NULL,
	street_name text NULL,
	cross_street_1 text NULL,
	cross_street_2 text NULL,
	address_type text NULL,
	city text NULL,
	facility_type text NULL,
	status text NULL,
	resolution_description text NULL,
	resolution_action_updated_date text NULL,
	community_board text NULL,
	police_precinct text NULL,
	borough text NULL,
	open_data_channel_type text NULL,
	park_facility_name text NULL,
	park_borough text NULL,
	descriptor_2 text NULL,
	location_type text NULL,
	intersection_street_1 text NULL,
	intersection_street_2 text NULL,
	landmark text NULL,
	council_district text NULL,
	bbl text NULL,
	x_coordinate_state_plane text NULL,
	y_coordinate_state_plane text NULL,
	latitude text NULL,
	longitude text NULL,
	"location" text NULL,
	vehicle_type text NULL,
	taxi_company_borough text NULL,
	taxi_pick_up_location text NULL,
	due_date text NULL,
	bridge_highway_name text NULL,
	bridge_highway_direction text NULL,
	road_ramp text NULL,
	bridge_highway_segment text NULL,
	CONSTRAINT service_requests_pkey PRIMARY KEY (unique_key)
);