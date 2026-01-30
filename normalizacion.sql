-- Limpieza por si existía antes
DROP TABLE IF EXISTS enrollments_raw;

CREATE TABLE enrollments_raw (
  student_id         INT,
  student_name       TEXT,
  student_email      TEXT,
  course_ids         TEXT, -- p.ej. 'MAT101|PHY101'
  course_names       TEXT, -- p.ej. 'Álgebra|Física'
  instr_names        TEXT, -- p.ej. 'Dra. Rojas|Dr. Vidal'
  instr_offices      TEXT  -- p.ej. 'B-201|A-105'
);

INSERT INTO enrollments_raw VALUES
(1, 'Ana Pérez',  'ana@uni.cl',
 'MAT101|PHY101', 'Álgebra|Física',
 'Dra. Rojas|Dr. Vidal', 'B-201|A-105'),
(2, 'Luis Soto',  'luis@uni.cl',
 'MAT101|HIS100', 'Álgebra|Historia',
 'Dra. Rojas|Mg. León', 'B-201|C-310');

-- comprobar
SELECT * FROM enrollments_raw;


-- =========================
-- PASO 1FN: enrollments_1fn
-- =========================

DROP TABLE IF EXISTS enrollments_1fn;

CREATE TABLE enrollments_1fn (
  student_id    INT NOT NULL,
  student_name  TEXT NOT NULL,
  student_email TEXT NOT NULL,
  course_id     TEXT NOT NULL,
  course_name   TEXT NOT NULL,
  instr_name    TEXT NOT NULL,
  instr_office  TEXT NOT NULL
);

INSERT INTO enrollments_1fn
SELECT
  student_id,
  student_name,
  student_email,
  split_part(course_ids,   '|', g.n) AS course_id,
  split_part(course_names, '|', g.n) AS course_name,
  split_part(instr_names,  '|', g.n) AS instr_name,
  split_part(instr_offices,'|', g.n) AS instr_office
FROM enrollments_raw
CROSS JOIN LATERAL generate_series(
  1,
  array_length(string_to_array(course_ids, '|'), 1)
) AS g(n);

-- comprobar
SELECT * FROM enrollments_1fn
ORDER BY student_id, course_id;


-- =========================
-- PASO 2FN
-- =========================

-- 1) Borrar tablas si ya existían
DROP TABLE IF EXISTS enrollments CASCADE;
DROP TABLE IF EXISTS courses CASCADE;
DROP TABLE IF EXISTS students CASCADE;

-- 2) Crear tabla de alumnos
CREATE TABLE students (
  student_id    INT PRIMARY KEY,
  student_name  TEXT NOT NULL,
  student_email TEXT NOT NULL UNIQUE
);

-- 3) Crear tabla de cursos
CREATE TABLE courses (
  course_id     TEXT PRIMARY KEY,
  course_name   TEXT NOT NULL,
  instr_name    TEXT NOT NULL,
  instr_office  TEXT NOT NULL
);

-- 4) Crear tabla de matrículas (relación alumno-curso)
CREATE TABLE enrollments (
  student_id INT NOT NULL REFERENCES students(student_id) ON DELETE CASCADE,
  course_id  TEXT NOT NULL REFERENCES courses(course_id)  ON DELETE CASCADE,
  PRIMARY KEY (student_id, course_id)
);

-- 5) Poblar students desde enrollments_1fn
INSERT INTO students(student_id, student_name, student_email)
SELECT DISTINCT student_id, student_name, student_email
FROM enrollments_1fn;

-- 6) Poblar courses desde enrollments_1fn
INSERT INTO courses(course_id, course_name, instr_name, instr_office)
SELECT DISTINCT course_id, course_name, instr_name, instr_office
FROM enrollments_1fn;

-- 7) Poblar enrollments (solo claves)
INSERT INTO enrollments(student_id, course_id)
SELECT DISTINCT student_id, course_id
FROM enrollments_1fn;

-- 8) Comprobar resultados
SELECT * FROM students    ORDER BY student_id;
SELECT * FROM courses     ORDER BY course_id;
SELECT * FROM enrollments ORDER BY student_id, course_id;


-- =========================
-- PASO 3FN
-- =========================

-- 1) Crear tabla de instructores
DROP TABLE IF EXISTS instructors CASCADE;

CREATE TABLE instructors (
  instr_name   TEXT PRIMARY KEY,
  instr_office TEXT NOT NULL
);

-- 2) Poblar instructores desde courses (sin duplicados)
INSERT INTO instructors(instr_name, instr_office)
SELECT DISTINCT instr_name, instr_office
FROM courses;

-- 3) Quitar la columna instr_office de courses
ALTER TABLE courses DROP COLUMN instr_office;

-- 4) Agregar FK desde courses hacia instructors
ALTER TABLE courses
  ADD CONSTRAINT fk_courses_instructor
  FOREIGN KEY (instr_name) REFERENCES instructors(instr_name);

-- 5) Comprobar resultado final
SELECT * FROM instructors ORDER BY instr_name;
SELECT course_id, course_name, instr_name FROM courses ORDER BY course_id;
SELECT * FROM enrollments ORDER BY student_id, course_id;


-- Consultas de comprobación

-- Alumnos con sus cursos e instructores (3FN)
SELECT s.student_name, s.student_email, c.course_id, c.course_name,
       i.instr_name, i.instr_office
FROM enrollments e
JOIN students    s ON s.student_id = e.student_id
JOIN courses     c ON c.course_id  = e.course_id
JOIN instructors i ON i.instr_name = c.instr_name
ORDER BY s.student_name, c.course_id;

-- ¿Cuántos alumnos por curso?
SELECT c.course_id, c.course_name, COUNT(*) AS alumnos
FROM enrollments e
JOIN courses c ON c.course_id = e.course_id
GROUP BY c.course_id, c.course_name
ORDER BY c.course_id;


-- Resumen:
-- 1FN: enrollments_1fn elimina listas en una celda.
-- 2FN: separa students, courses y enrollments para quitar dependencias parciales.
-- 3FN: crea instructors y elimina la dependencia transitiva de instr_office.
