-- DEVELOPMENT ONLY: deletes everything in the public schema.
DROP SCHEMA IF EXISTS extensions CASCADE;
DROP SCHEMA public CASCADE;
CREATE SCHEMA public;
GRANT ALL ON SCHEMA public TO public;