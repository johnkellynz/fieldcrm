WITH numbered AS (
  SELECT id, ROW_NUMBER() OVER (ORDER BY company_name) AS rn
  FROM kac_accounts
),
pool AS (
  SELECT
    ARRAY['James','Sarah','Mark','Lisa','David','Emma','Tom','Rachel','Michael','Kate',
          'Chris','Priya','Nathan','Jessica','Ryan','Olivia','Daniel','Sophie','Andrew','Megan',
          'Peter','Hannah','Simon','Amy','Ben','Laura','Marcus','Chloe','Jake','Tanya',
          'Paul','Fiona','Luke','Nina','Sam','Rebecca','Owen','Grace','Alex','Holly'] AS fn,
    ARRAY['Mitchell','Chen','Sullivan','Patel','Wong','Richards','Baker','Kim','Williams','Taylor',
          'Sharma','Lee','Adams','Cooper','Martin','Hughes','Clark','Scott','Brown','Nguyen',
          'Davies','Fraser','Robertson','Walker','Johnson','Hall','Stewart','Edwards','Moore','Bennett',
          'Campbell','Anderson','Kapoor','Dixon','Young','Phillips','Murphy','Turner','Price','Liu'] AS ln,
    ARRAY['Estimating Manager','Project Engineer','Procurement Manager','BIM / Technical Lead',
          'Site Foreman / Supervisor','MD / Director / Owner','HSE Manager','Operations Manager',
          'Facilities Manager','Mechanical Lead'] AS rl
),
slots AS (
  SELECT n.id, n.rn, s AS slot
  FROM numbered n
  CROSS JOIN generate_series(1, 3) AS s
)
INSERT INTO kac_contacts (account_id, contact_name, role, is_key_influencer)
SELECT
  sl.id,
  p.fn[1 + ((sl.rn * 3 + sl.slot * 7)  % 40)] || ' ' ||
  p.ln[1 + ((sl.rn * 5 + sl.slot * 11) % 40)],
  p.rl[1 + ((sl.rn + sl.slot) % 10)],
  (sl.slot = 1)
FROM slots sl
CROSS JOIN pool p;
