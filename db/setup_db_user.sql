/* intentional: this will not drop and recreate the database if it already exists */
/* Mainly for CI. If you install with brew, you likely have authentication configured as "TRUST" for all */
CREATE USER nexia WITH PASSWORD 'Password1';
GRANT ALL ON DATABASE history_store TO nexia;
