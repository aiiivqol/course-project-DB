-- Создание хранимой процедуры для заполнения таблицы "Расписание" с проверкой вводимых значений

CREATE OR REPLACE PROCEDURE generate_timetable(
  film_title VARCHAR(100),
  hall_name VARCHAR(100),
  start_date DATE,
  end_date DATE,
  time_coefficients JSONB,
  status VARCHAR(20)
)
AS $$
DECLARE
  film_id INTEGER;
  hall_id INTEGER;
  curr_date DATE;
  start_time TIME;
  time_coefficient FLOAT;
  details_json JSONB;
BEGIN
  -- Проверка существования фильма в таблице info_films
  SELECT id_film INTO film_id FROM info_films WHERE title = film_title;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Фильм с названием "%", указанным в параметрах, не найден в базе данных.', film_title;
  END IF;
  
  -- Проверка существования зала в таблице halls
  SELECT id_hall INTO hall_id FROM halls WHERE name = hall_name;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Зал с названием "%", указанным в параметрах, не найден в базе данных.', hall_name;
  END IF;
  
  curr_date := start_date;
  
  -- Цикл по датам
  WHILE curr_date <= end_date LOOP
    -- Парсинг временных коэффициентов
    FOR i IN 0..jsonb_array_length(time_coefficients)-1 LOOP
      start_time := (time_coefficients->i->>'time')::TIME;
      time_coefficient := (time_coefficients->i->>'coefficient')::FLOAT;
      
      -- Создание JSONB-объекта для поля details
      details_json := jsonb_build_object('date', to_char(curr_date, 'YYYY-MM-DD'), 'time', to_char(start_time, 'HH24:MI'), 'coefficient', time_coefficient);
      
      -- Вставка записи в таблицу "Расписание"
      INSERT INTO timetable (id_film, id_hall, details, status)
      VALUES (film_id, hall_id, details_json, status);
    END LOOP;
    
    curr_date := curr_date + 1; -- Переход к следующей дате
  END LOOP;
  
  RAISE NOTICE 'Расписание успешно сгенерировано.';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Ошибка: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

select * from halls
-- Вызов хранимой процедуры для заполнения расписания
CALL generate_timetable('Фильм 2', 'Зал 1', '2024-05-15', '2024-06-15',
                        '[{"time": "09:00", "coefficient": 1.1},
                          {"time": "12:00", "coefficient": 1.5},
                          {"time": "21:00", "coefficient": 1.6}]',
                        'В прокате');
            
select * from timetable
select * from tickets
select * from info_films
select * from halls

delete from timetable
delete from tickets



---

select * from tickets


---- Генерация билетов на сеанс

CREATE OR REPLACE FUNCTION generate_tickets()
RETURNS TRIGGER AS $$
DECLARE
  hall_row_count INTEGER;
  hall_seat_count INTEGER;
  curr_row INTEGER;
  curr_seat INTEGER;
  ticket_price NUMERIC(10, 2);
  hall_coefficient NUMERIC(10, 2);
  timetable_coefficient NUMERIC(10, 2);
BEGIN
  -- Получение количества рядов и мест в зале
  SELECT rows, seats, coefficient INTO hall_row_count, hall_seat_count, hall_coefficient
  FROM halls
  WHERE id_hall = (
    SELECT id_hall FROM timetable WHERE id_timetable = NEW.id_timetable
  );

  curr_row := 1;
  curr_seat := 1;

  -- Получение коэффициента из деталей расписания
  SELECT (NEW.details->>'coefficient')::NUMERIC INTO timetable_coefficient;

  -- Генерация записей в таблицу "tickets" для каждого ряда и места
  WHILE curr_row <= hall_row_count LOOP
    WHILE curr_seat <= hall_seat_count LOOP
      -- Получение базовой цены из таблицы halls
      SELECT def_price INTO ticket_price
      FROM halls
      WHERE id_hall = (
        SELECT id_hall FROM timetable WHERE id_timetable = NEW.id_timetable
      );

      -- Проверка совпадения с bestrows и bestseats
      IF curr_row = ANY(ARRAY(SELECT jsonb_array_elements_text(bestrows)::INTEGER FROM halls WHERE id_hall = NEW.id_hall)::INTEGER[]) AND
         curr_seat = ANY(ARRAY(SELECT jsonb_array_elements_text(bestseats)::INTEGER FROM halls WHERE id_hall = NEW.id_hall)::INTEGER[]) THEN
        ticket_price := ticket_price * hall_coefficient * timetable_coefficient;
      ELSE
        ticket_price := ticket_price * timetable_coefficient;
      END IF;
	  -- Вставка записи в таблицу "tickets"
      INSERT INTO tickets (id_row, id_seat, id_timetable, price, status)
      VALUES (curr_row, curr_seat, NEW.id_timetable, ticket_price, 1);

      curr_seat := curr_seat + 1; -- Переход к следующему месту
    END LOOP;

    curr_row := curr_row + 1; -- Переход к следующему ряду
    curr_seat := 1; -- Сброс счетчика мест
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- Создание триггера после вставки в таблицу "timetable"
CREATE or replace TRIGGER generate_tickets_trigger
AFTER INSERT ON timetable
FOR EACH ROW
EXECUTE FUNCTION generate_tickets();




-- На удаление сеанса:

-- Создание функции для удаления связанных билетов
CREATE OR REPLACE FUNCTION delete_related_tickets()
RETURNS TRIGGER AS $$
BEGIN
  -- Удаление билетов, связанных с удаляемой записью из таблицы "timetable"
  DELETE FROM tickets
  WHERE id_timetable = OLD.id_timetable;

  RETURN OLD;
END;
$$ LANGUAGE plpgsql;



-- Создание триггера для удаления связанных билетов после удаления записи из таблицы "timetable"
CREATE TRIGGER delete_related_tickets_trigger
AFTER DELETE ON timetable
FOR EACH ROW
EXECUTE FUNCTION delete_related_tickets();



-- Процедура удаления
CREATE OR REPLACE PROCEDURE delete_movie_from_timetable(
    film_title VARCHAR(100),
    hall_name VARCHAR(100),
    theater_name VARCHAR(100)
)
AS $$
DECLARE
    film_id INTEGER;
    hall_id INTEGER;
    theater_id INTEGER;
BEGIN
    -- Получение идентификатора фильма по названию
    SELECT id_film INTO film_id FROM info_films WHERE title = film_title;
    
    -- Получение идентификатора зала и кинотеатра по их названиям
    SELECT h.id_hall, t.id_theater INTO hall_id, theater_id
    FROM halls h
    INNER JOIN theaters t ON h.id_theater = t.id_theater
    WHERE h.name = hall_name AND t.name = theater_name;

    -- Проверка наличия записи о фильме в заданном зале и кинотеатре
    IF NOT EXISTS (
        SELECT 1 FROM timetable
        WHERE id_film = film_id AND id_hall = hall_id
    ) THEN
        RAISE NOTICE 'Некорректные данные. Фильм "%s" не показывается в зале "%s" кинотеатра "%s".', film_title, hall_name, theater_name;
        RETURN;
    END IF;

    -- Удаление связанных билетов из таблицы "tickets"
    DELETE FROM tickets
    WHERE id_timetable IN (
        SELECT id_timetable FROM timetable
        WHERE id_film = film_id AND id_hall = hall_id
    );

    -- Удаление записи из таблицы "timetable" по заданным условиям
    DELETE FROM timetable
    WHERE id_film = film_id AND id_hall = hall_id;

    RAISE NOTICE 'Запись о фильме "%", показываемом в зале "%", кинотеатра "%", успешно удалена из расписания.', film_title, hall_name, theater_name;
END;
$$ LANGUAGE plpgsql;

-- Вызов процедуры удаления

CALL delete_movie_from_timetable('Фильм 2', 'Зал 1', 'Кинотеатр 2');












---- Процедура на изменение:

-- Создание процедуры для изменения расписания фильма
drop procedure update_timetable_entry
CREATE OR REPLACE PROCEDURE update_timetable_entry(
  film_title VARCHAR(100),
  hall_name VARCHAR(100),
  start_date DATE,
  end_date DATE,
  time_coefficients JSONB,
  status VARCHAR(20)
)
AS $$
DECLARE
  film_id INTEGER;
  hall_id INTEGER;
  curr_date DATE;
  start_time TIME;
  time_coefficient FLOAT;
  details_json JSONB;
BEGIN
  -- Проверка существования фильма в таблице info_films
  SELECT id_film INTO film_id FROM info_films WHERE title = film_title;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Фильм с названием "%", указанным в параметрах, не найден в базе данных.', film_title;
  END IF;
  
  -- Проверка существования зала в таблице halls
  SELECT id_hall INTO hall_id FROM halls WHERE name = hall_name;
  IF NOT FOUND THEN
    RAISE EXCEPTION 'Зал с названием "%", указанным в параметрах, не найден в базе данных.', hall_name;
  END IF;
  
  curr_date := start_date;
   DELETE FROM tickets
  WHERE id_timetable IN (
    SELECT id_timetable FROM timetable
    WHERE id_film = film_id AND id_hall = hall_id
      AND details->>'date' >= to_char(start_date, 'YYYY-MM-DD')
      AND details->>'date' <= to_char(end_date, 'YYYY-MM-DD')
  ); 
  -- Удаление существующих записей в таблице "Расписание" для указанного фильма, зала и периода
  DELETE FROM timetable
  WHERE id_film = film_id AND id_hall = hall_id AND details->>'date' >= to_char(start_date, 'YYYY-MM-DD') AND details->>'date' <= to_char(end_date, 'YYYY-MM-DD');
  
  -- Удаление связанных записей в таблице "tickets"

  
  -- Цикл по датам
  WHILE curr_date <= end_date LOOP
    -- Парсинг временных коэффициентов
    FOR i IN 0..jsonb_array_length(time_coefficients)-1 LOOP
      start_time := (time_coefficients->i->>'time')::TIME;
      time_coefficient := (time_coefficients->i->>'coefficient')::FLOAT;
      
      -- Создание JSONB-объекта для поля details
      details_json := jsonb_build_object('date', to_char(curr_date, 'YYYY-MM-DD'), 'time', to_char(start_time, 'HH24:MI'), 'coefficient', time_coefficient);
      
      -- Вставка записи в таблицу "Расписание"
      INSERT INTO timetable (id_film, id_hall, details, status)
      VALUES (film_id, hall_id, details_json, status);
    END LOOP;
    
    curr_date := curr_date + 1; -- Переход к следующей дате
  END LOOP;
  
  RAISE NOTICE 'Расписание успешно обновлено.';
EXCEPTION
  WHEN OTHERS THEN
    RAISE NOTICE 'Ошибка: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


-- Создание триггера для обновления таблицы tickets после изменения в таблице timetable
CREATE OR REPLACE FUNCTION update_tickets_on_timetable_update()
RETURNS TRIGGER AS $$
DECLARE
  hall_row_count INTEGER;
  hall_seat_count INTEGER;
  curr_row INTEGER;
  curr_seat INTEGER;
  ticket_price NUMERIC(10, 2);
  hall_coefficient NUMERIC(10, 2);
  timetable_coefficient NUMERIC(10, 2);
BEGIN
  -- Получение количества рядов и мест в зале
  SELECT rows, seats, coefficient INTO hall_row_count, hall_seat_count, hall_coefficient
  FROM halls
  WHERE id_hall = (
    SELECT id_hall FROM timetable WHERE id_timetable = NEW.id_timetable
  );

  curr_row := 1;
  curr_seat := 1;

  -- Получение коэффициента из деталей расписания
  SELECT (NEW.details->>'coefficient')::NUMERIC INTO timetable_coefficient;

  -- Обновление данных в таблице "tickets" для каждого ряда и места
  WHILE curr_row <= hall_row_count LOOP
    WHILE curr_seat <= hall_seat_count LOOP
      -- Получение базовой цены из таблицы halls
      SELECT def_price INTO ticket_price
      FROM halls
      WHERE id_hall = (
        SELECT id_hall FROM timetable WHERE id_timetable = NEW.id_timetable
      );

      -- Проверка совпадения с bestrows и bestseats
      IF curr_row = ANY(ARRAY(SELECT jsonb_array_elements_text(bestrows)::INTEGER FROM halls WHERE id_hall = NEW.id_hall)::INTEGER[]) AND
         curr_seat = ANY(ARRAY(SELECT jsonb_array_elements_text(bestseats)::INTEGER FROM halls WHERE id_hall = NEW.id_hall)::INTEGER[]) THEN
        ticket_price := ticket_price * hall_coefficient * timetable_coefficient;
      ELSE
        ticket_price := ticket_price * timetable_coefficient;
      END IF;

      -- Обновление записи в таблице "tickets"
      UPDATE tickets
      SET price = ticket_price,
          status = CASE WHEN NEW.status = 'В прокате' THEN 1 ELSE 0 END
      WHERE id_row = curr_row
        AND id_seat = curr_seat
        AND id_timetable = NEW.id_timetable;

      curr_seat := curr_seat + 1; -- Переход к следующему месту
    END LOOP;

    curr_row := curr_row + 1; -- Переход к следующему ряду
    curr_seat := 1; -- Сброс счетчика мест
  END LOOP;

  RETURN NEW;
END;
$$ LANGUAGE plpgsql;


-- Создание триггера после изменения в таблице timetable
CREATE TRIGGER update_tickets_trigger
AFTER UPDATE ON timetable
FOR EACH ROW
EXECUTE PROCEDURE update_tickets_on_timetable_update();


select * from timetable
select * from tickets
select * from halls

CALL update_timetable_entry('Фильм 2', 'Зал 1', 
                            '2024-05-17', '2024-06-17',
                        '[{"time": "12:00", "coefficient": 1.0},
                          {"time": "18:00", "coefficient": 1.3},
                          {"time": "21:00", "coefficient": 1.6}]',
                            'В прокате');