-- characterization corpus: check 1 (destructive DDL keywords)
-- positives
ALTER TABLE users DROP COLUMN legacy_flag;
DROP TABLE archived_users;
ALTER TABLE orders ALTER COLUMN total TYPE numeric(12,2);
ALTER TABLE orders RENAME COLUMN amount TO total;
ALTER TABLE t DROP COLUMN a, RENAME COLUMN b TO c;
alter table sessions drop column token;
ALTER	TABLE	tabs	DROP	COLUMN	x;
-- negatives: word-boundary and non-destructive DDL
CREATE TABLE metrics (id serial primary key, label text NOT NULL);
ALTER TABLE metrics ADD COLUMN note text;
CREATE INDEX metrics_label_idx ON metrics (label);
SELECT dropcolumn FROM legacy_helpers;
SELECT * FROM renamed_columns;
UPDATE flags SET no_rename_here = true;
SELECT typex FROM alter_helpers;
