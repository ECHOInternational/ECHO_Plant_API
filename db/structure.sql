SET statement_timeout = 0;
SET lock_timeout = 0;
SET idle_in_transaction_session_timeout = 0;
SET client_encoding = 'UTF8';
SET standard_conforming_strings = on;
SELECT pg_catalog.set_config('search_path', '', false);
SET check_function_bodies = false;
SET xmloption = content;
SET client_min_messages = warning;
SET row_security = off;

--
-- Name: pgcrypto; Type: EXTENSION; Schema: -; Owner: -
--

CREATE EXTENSION IF NOT EXISTS pgcrypto WITH SCHEMA public;


--
-- Name: EXTENSION pgcrypto; Type: COMMENT; Schema: -; Owner: -
--

COMMENT ON EXTENSION pgcrypto IS 'cryptographic functions';


--
-- Name: early_growth_phase; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.early_growth_phase AS ENUM (
    'slow',
    'intermediate',
    'fast'
);


--
-- Name: life_cycle; Type: TYPE; Schema: public; Owner: -
--

CREATE TYPE public.life_cycle AS ENUM (
    'annual',
    'biennial',
    'perennial'
);


SET default_tablespace = '';

SET default_with_oids = false;

--
-- Name: antinutrients; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.antinutrients (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: antinutrients_plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.antinutrients_plants (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    antinutrient_id uuid NOT NULL,
    plant_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: antinutrients_varieties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.antinutrients_varieties (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    antinutrient_id uuid NOT NULL,
    variety_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: ar_internal_metadata; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.ar_internal_metadata (
    key character varying NOT NULL,
    value character varying,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: categories; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying NOT NULL,
    owned_by character varying NOT NULL,
    visibility integer DEFAULT 0 NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: categories_plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.categories_plants (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    category_id uuid NOT NULL,
    plant_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: common_names; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.common_names (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    name character varying NOT NULL,
    language character varying NOT NULL,
    location character varying,
    plant_id uuid NOT NULL,
    "primary" boolean DEFAULT false NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: growth_habits; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.growth_habits (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: growth_habits_plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.growth_habits_plants (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    growth_habit_id uuid NOT NULL,
    plant_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: growth_habits_varieties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.growth_habits_varieties (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    growth_habit_id uuid NOT NULL,
    variety_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: image_attributes; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.image_attributes (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: image_attributes_images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.image_attributes_images (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    image_attribute_id uuid NOT NULL,
    image_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: images; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.images (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    attribution character varying,
    s3_bucket character varying NOT NULL,
    s3_key character varying NOT NULL,
    created_by character varying NOT NULL,
    owned_by character varying NOT NULL,
    visibility integer DEFAULT 0 NOT NULL,
    imageable_type character varying NOT NULL,
    imageable_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.plants (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying NOT NULL,
    owned_by character varying NOT NULL,
    visibility integer DEFAULT 0 NOT NULL,
    scientific_name character varying,
    family_names character varying,
    n_accumulation_range int4range DEFAULT '[0,1)'::int4range,
    biomass_production_range numrange DEFAULT '[0.0,0.0]'::numrange,
    optimal_temperature_range int4range DEFAULT '[0,61)'::int4range,
    optimal_rainfall_range int4range DEFAULT '[0,)'::int4range,
    seasonality_days_range int4range,
    optimal_altitude_range int4range DEFAULT '[0,)'::int4range,
    ph_range numrange DEFAULT '[0.0,14.0]'::numrange,
    has_edible_green_leaves boolean,
    has_edible_immature_fruit boolean,
    has_edible_mature_fruit boolean,
    can_be_used_for_fodder boolean,
    early_growth_phase public.early_growth_phase,
    life_cycle public.life_cycle,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: schema_migrations; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.schema_migrations (
    version character varying NOT NULL
);


--
-- Name: tolerances; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tolerances (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tolerances_plants; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tolerances_plants (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    tolerance_id uuid NOT NULL,
    plant_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: tolerances_varieties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.tolerances_varieties (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    tolerance_id uuid NOT NULL,
    variety_id uuid NOT NULL,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: varieties; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.varieties (
    id uuid DEFAULT public.gen_random_uuid() NOT NULL,
    plant_id uuid NOT NULL,
    translations jsonb DEFAULT '{}'::jsonb NOT NULL,
    created_by character varying NOT NULL,
    owned_by character varying NOT NULL,
    visibility integer DEFAULT 0 NOT NULL,
    n_accumulation_range int4range DEFAULT '[0,1)'::int4range,
    biomass_production_range numrange DEFAULT '[0.0,0.0]'::numrange,
    optimal_temperature_range int4range DEFAULT '[0,61)'::int4range,
    optimal_rainfall_range int4range DEFAULT '[0,)'::int4range,
    seasonality_days_range int4range,
    optimal_altitude_range int4range DEFAULT '[0,)'::int4range,
    ph_range numrange DEFAULT '[0.0,14.0]'::numrange,
    has_edible_green_leaves boolean,
    has_edible_immature_fruit boolean,
    has_edible_mature_fruit boolean,
    can_be_used_for_fodder boolean,
    created_at timestamp(6) without time zone NOT NULL,
    updated_at timestamp(6) without time zone NOT NULL
);


--
-- Name: versions; Type: TABLE; Schema: public; Owner: -
--

CREATE TABLE public.versions (
    id bigint NOT NULL,
    item_type character varying NOT NULL,
    item_id bigint NOT NULL,
    event character varying NOT NULL,
    whodunnit character varying,
    object text,
    created_at timestamp without time zone,
    object_changes text
);


--
-- Name: versions_id_seq; Type: SEQUENCE; Schema: public; Owner: -
--

CREATE SEQUENCE public.versions_id_seq
    START WITH 1
    INCREMENT BY 1
    NO MINVALUE
    NO MAXVALUE
    CACHE 1;


--
-- Name: versions_id_seq; Type: SEQUENCE OWNED BY; Schema: public; Owner: -
--

ALTER SEQUENCE public.versions_id_seq OWNED BY public.versions.id;


--
-- Name: versions id; Type: DEFAULT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions ALTER COLUMN id SET DEFAULT nextval('public.versions_id_seq'::regclass);


--
-- Name: antinutrients antinutrients_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients
    ADD CONSTRAINT antinutrients_pkey PRIMARY KEY (id);


--
-- Name: antinutrients_plants antinutrients_plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_plants
    ADD CONSTRAINT antinutrients_plants_pkey PRIMARY KEY (id);


--
-- Name: antinutrients_varieties antinutrients_varieties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_varieties
    ADD CONSTRAINT antinutrients_varieties_pkey PRIMARY KEY (id);


--
-- Name: ar_internal_metadata ar_internal_metadata_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.ar_internal_metadata
    ADD CONSTRAINT ar_internal_metadata_pkey PRIMARY KEY (key);


--
-- Name: categories categories_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories
    ADD CONSTRAINT categories_pkey PRIMARY KEY (id);


--
-- Name: categories_plants categories_plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories_plants
    ADD CONSTRAINT categories_plants_pkey PRIMARY KEY (id);


--
-- Name: common_names common_names_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_names
    ADD CONSTRAINT common_names_pkey PRIMARY KEY (id);


--
-- Name: growth_habits growth_habits_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits
    ADD CONSTRAINT growth_habits_pkey PRIMARY KEY (id);


--
-- Name: growth_habits_plants growth_habits_plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_plants
    ADD CONSTRAINT growth_habits_plants_pkey PRIMARY KEY (id);


--
-- Name: growth_habits_varieties growth_habits_varieties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_varieties
    ADD CONSTRAINT growth_habits_varieties_pkey PRIMARY KEY (id);


--
-- Name: image_attributes_images image_attributes_images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_attributes_images
    ADD CONSTRAINT image_attributes_images_pkey PRIMARY KEY (id);


--
-- Name: image_attributes image_attributes_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_attributes
    ADD CONSTRAINT image_attributes_pkey PRIMARY KEY (id);


--
-- Name: images images_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.images
    ADD CONSTRAINT images_pkey PRIMARY KEY (id);


--
-- Name: plants plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.plants
    ADD CONSTRAINT plants_pkey PRIMARY KEY (id);


--
-- Name: schema_migrations schema_migrations_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.schema_migrations
    ADD CONSTRAINT schema_migrations_pkey PRIMARY KEY (version);


--
-- Name: tolerances tolerances_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances
    ADD CONSTRAINT tolerances_pkey PRIMARY KEY (id);


--
-- Name: tolerances_plants tolerances_plants_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_plants
    ADD CONSTRAINT tolerances_plants_pkey PRIMARY KEY (id);


--
-- Name: tolerances_varieties tolerances_varieties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_varieties
    ADD CONSTRAINT tolerances_varieties_pkey PRIMARY KEY (id);


--
-- Name: varieties varieties_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.varieties
    ADD CONSTRAINT varieties_pkey PRIMARY KEY (id);


--
-- Name: versions versions_pkey; Type: CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.versions
    ADD CONSTRAINT versions_pkey PRIMARY KEY (id);


--
-- Name: index_antinutrients_plants_on_antinutrient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_antinutrients_plants_on_antinutrient_id ON public.antinutrients_plants USING btree (antinutrient_id);


--
-- Name: index_antinutrients_plants_on_antinutrient_id_and_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_antinutrients_plants_on_antinutrient_id_and_plant_id ON public.antinutrients_plants USING btree (antinutrient_id, plant_id);


--
-- Name: index_antinutrients_plants_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_antinutrients_plants_on_plant_id ON public.antinutrients_plants USING btree (plant_id);


--
-- Name: index_antinutrients_varieties_on_antinutrient_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_antinutrients_varieties_on_antinutrient_id ON public.antinutrients_varieties USING btree (antinutrient_id);


--
-- Name: index_antinutrients_varieties_on_antinutrient_id_and_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_antinutrients_varieties_on_antinutrient_id_and_variety_id ON public.antinutrients_varieties USING btree (antinutrient_id, variety_id);


--
-- Name: index_antinutrients_varieties_on_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_antinutrients_varieties_on_variety_id ON public.antinutrients_varieties USING btree (variety_id);


--
-- Name: index_categories_plants_on_category_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_plants_on_category_id ON public.categories_plants USING btree (category_id);


--
-- Name: index_categories_plants_on_category_id_and_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_categories_plants_on_category_id_and_plant_id ON public.categories_plants USING btree (category_id, plant_id);


--
-- Name: index_categories_plants_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_categories_plants_on_plant_id ON public.categories_plants USING btree (plant_id);


--
-- Name: index_common_names_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_common_names_on_plant_id ON public.common_names USING btree (plant_id);


--
-- Name: index_growth_habits_plants_on_growth_habit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_growth_habits_plants_on_growth_habit_id ON public.growth_habits_plants USING btree (growth_habit_id);


--
-- Name: index_growth_habits_plants_on_growth_habit_id_and_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_growth_habits_plants_on_growth_habit_id_and_plant_id ON public.growth_habits_plants USING btree (growth_habit_id, plant_id);


--
-- Name: index_growth_habits_plants_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_growth_habits_plants_on_plant_id ON public.growth_habits_plants USING btree (plant_id);


--
-- Name: index_growth_habits_varieties_on_growth_habit_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_growth_habits_varieties_on_growth_habit_id ON public.growth_habits_varieties USING btree (growth_habit_id);


--
-- Name: index_growth_habits_varieties_on_growth_habit_id_and_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_growth_habits_varieties_on_growth_habit_id_and_variety_id ON public.growth_habits_varieties USING btree (growth_habit_id, variety_id);


--
-- Name: index_growth_habits_varieties_on_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_growth_habits_varieties_on_variety_id ON public.growth_habits_varieties USING btree (variety_id);


--
-- Name: index_image_attributes_image_on_both_ids; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_image_attributes_image_on_both_ids ON public.image_attributes_images USING btree (image_id, image_attribute_id);


--
-- Name: index_image_attributes_images_on_image_attribute_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_attributes_images_on_image_attribute_id ON public.image_attributes_images USING btree (image_attribute_id);


--
-- Name: index_image_attributes_images_on_image_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_image_attributes_images_on_image_id ON public.image_attributes_images USING btree (image_id);


--
-- Name: index_images_on_imageable_type_and_imageable_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_images_on_imageable_type_and_imageable_id ON public.images USING btree (imageable_type, imageable_id);


--
-- Name: index_tolerances_plants_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tolerances_plants_on_plant_id ON public.tolerances_plants USING btree (plant_id);


--
-- Name: index_tolerances_plants_on_tolerance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tolerances_plants_on_tolerance_id ON public.tolerances_plants USING btree (tolerance_id);


--
-- Name: index_tolerances_plants_on_tolerance_id_and_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tolerances_plants_on_tolerance_id_and_plant_id ON public.tolerances_plants USING btree (tolerance_id, plant_id);


--
-- Name: index_tolerances_varieties_on_tolerance_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tolerances_varieties_on_tolerance_id ON public.tolerances_varieties USING btree (tolerance_id);


--
-- Name: index_tolerances_varieties_on_tolerance_id_and_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE UNIQUE INDEX index_tolerances_varieties_on_tolerance_id_and_variety_id ON public.tolerances_varieties USING btree (tolerance_id, variety_id);


--
-- Name: index_tolerances_varieties_on_variety_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_tolerances_varieties_on_variety_id ON public.tolerances_varieties USING btree (variety_id);


--
-- Name: index_varieties_on_plant_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_varieties_on_plant_id ON public.varieties USING btree (plant_id);


--
-- Name: index_versions_on_item_type_and_item_id; Type: INDEX; Schema: public; Owner: -
--

CREATE INDEX index_versions_on_item_type_and_item_id ON public.versions USING btree (item_type, item_id);


--
-- Name: tolerances_varieties fk_rails_010cc18129; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_varieties
    ADD CONSTRAINT fk_rails_010cc18129 FOREIGN KEY (variety_id) REFERENCES public.varieties(id);


--
-- Name: antinutrients_plants fk_rails_0d9647da63; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_plants
    ADD CONSTRAINT fk_rails_0d9647da63 FOREIGN KEY (antinutrient_id) REFERENCES public.antinutrients(id);


--
-- Name: varieties fk_rails_143fdc3592; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.varieties
    ADD CONSTRAINT fk_rails_143fdc3592 FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: antinutrients_plants fk_rails_41db3c11c4; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_plants
    ADD CONSTRAINT fk_rails_41db3c11c4 FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: growth_habits_varieties fk_rails_5f4cf82393; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_varieties
    ADD CONSTRAINT fk_rails_5f4cf82393 FOREIGN KEY (variety_id) REFERENCES public.varieties(id);


--
-- Name: growth_habits_plants fk_rails_60c1d5f98e; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_plants
    ADD CONSTRAINT fk_rails_60c1d5f98e FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: antinutrients_varieties fk_rails_68c484669b; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_varieties
    ADD CONSTRAINT fk_rails_68c484669b FOREIGN KEY (antinutrient_id) REFERENCES public.antinutrients(id);


--
-- Name: tolerances_plants fk_rails_71ff34f866; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_plants
    ADD CONSTRAINT fk_rails_71ff34f866 FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: categories_plants fk_rails_79aa045ff3; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories_plants
    ADD CONSTRAINT fk_rails_79aa045ff3 FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: antinutrients_varieties fk_rails_84dac3ad75; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.antinutrients_varieties
    ADD CONSTRAINT fk_rails_84dac3ad75 FOREIGN KEY (variety_id) REFERENCES public.varieties(id);


--
-- Name: growth_habits_varieties fk_rails_9086b6b920; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_varieties
    ADD CONSTRAINT fk_rails_9086b6b920 FOREIGN KEY (growth_habit_id) REFERENCES public.growth_habits(id);


--
-- Name: image_attributes_images fk_rails_9a12e7d877; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_attributes_images
    ADD CONSTRAINT fk_rails_9a12e7d877 FOREIGN KEY (image_attribute_id) REFERENCES public.image_attributes(id);


--
-- Name: tolerances_plants fk_rails_a3254e6389; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_plants
    ADD CONSTRAINT fk_rails_a3254e6389 FOREIGN KEY (tolerance_id) REFERENCES public.tolerances(id);


--
-- Name: growth_habits_plants fk_rails_bc7bc6a045; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.growth_habits_plants
    ADD CONSTRAINT fk_rails_bc7bc6a045 FOREIGN KEY (growth_habit_id) REFERENCES public.growth_habits(id);


--
-- Name: categories_plants fk_rails_d29e534eae; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.categories_plants
    ADD CONSTRAINT fk_rails_d29e534eae FOREIGN KEY (category_id) REFERENCES public.categories(id);


--
-- Name: common_names fk_rails_e1c5a1a6cd; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.common_names
    ADD CONSTRAINT fk_rails_e1c5a1a6cd FOREIGN KEY (plant_id) REFERENCES public.plants(id);


--
-- Name: image_attributes_images fk_rails_e3ccc8f28f; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.image_attributes_images
    ADD CONSTRAINT fk_rails_e3ccc8f28f FOREIGN KEY (image_id) REFERENCES public.images(id);


--
-- Name: tolerances_varieties fk_rails_ecd614b85d; Type: FK CONSTRAINT; Schema: public; Owner: -
--

ALTER TABLE ONLY public.tolerances_varieties
    ADD CONSTRAINT fk_rails_ecd614b85d FOREIGN KEY (tolerance_id) REFERENCES public.tolerances(id);


--
-- PostgreSQL database dump complete
--

SET search_path TO "$user", public;

INSERT INTO "schema_migrations" (version) VALUES
('20200702173418'),
('20200702173419'),
('20200702191256'),
('20200725194221'),
('20200801021051'),
('20200802015638'),
('20200802233703'),
('20200814173300'),
('20200814173311'),
('20200814173322'),
('20200817142731'),
('20200817173929'),
('20200817180807'),
('20200817182822'),
('20200817184430'),
('20200817193432'),
('20200819084701');


