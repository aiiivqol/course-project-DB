-- Может изменять список фильмов в прокате


CREATE OR REPLACE PROCEDURE add_movie_to_catalog(
  movie_title VARCHAR(255),
  movie_genre VARCHAR(255),
  movie_rating FLOAT,
  movie_description VARCHAR(2000)
)
security definer
AS $$
BEGIN

  IF EXISTS (SELECT 1 FROM info_films WHERE title = movie_title) THEN
    RAISE EXCEPTION 'Фильм с названием "%", уже присутствует в каталоге.', movie_title;
  END IF;
  
  INSERT INTO info_films (title, genre, rating, description)
  VALUES (movie_title, movie_genre, movie_rating, movie_description);
  
  RAISE NOTICE 'Фильм "%", успешно добавлен в каталог.', movie_title;
END;
$$ LANGUAGE plpgsql;

CALL add_movie_to_catalog('Крутой фильм', 'Драма', 4.5, 'Описание крутого фильма.');


select * from info_films




--- Удаление существующего фильма из проката
CREATE OR REPLACE PROCEDURE delete_movie_from_catalog(
    film_title VARCHAR(255)
)
security definer
AS $$
BEGIN
    IF NOT EXISTS (SELECT 1 FROM info_films WHERE title = film_title) THEN
        RAISE EXCEPTION 'Фильм "%" не найден в каталоге.', film_title;
    END IF;
    
    DELETE FROM info_films
    WHERE title = film_title;
    
    RAISE NOTICE 'Фильм "%", успешно удален из каталога.', film_title;
END;
$$ LANGUAGE plpgsql;

CALL delete_movie_from_catalog('Крутой фильм');




-- Добавление администратора

CREATE OR REPLACE PROCEDURE add_administrator(
    admin_name VARCHAR(255),
    admin_password VARCHAR(255),
    admin_email VARCHAR(255)
)
security definer
AS $$
BEGIN
    IF EXISTS (SELECT 1 FROM administrators WHERE name = admin_name) THEN
        RAISE EXCEPTION 'Администратор с именем "%s" уже существует.', admin_name;
    END IF;
    
    IF EXISTS (SELECT 1 FROM administrators WHERE email = admin_email) THEN
        RAISE EXCEPTION 'Администратор с почтой "%s" уже существует.', admin_email;
    END IF;

    INSERT INTO administrators (name, password, email) VALUES (admin_name, admin_password, admin_email);

    RAISE NOTICE 'Администратор "%s" успешно добавлен.', admin_name;
END;
$$ LANGUAGE plpgsql;



CREATE OR REPLACE PROCEDURE delete_admin(
    admin_name_to_delete VARCHAR(255)
) 
security definer
AS $$
DECLARE
    admin_id_to_delete INTEGER;
    new_admin_id INTEGER;
    admin_name_to_replace VARCHAR(255);
BEGIN
    SELECT id_admin INTO admin_id_to_delete FROM administrators WHERE name = admin_name_to_delete;

    IF admin_id_to_delete IS NULL THEN
        RAISE EXCEPTION 'Администратор с именем "%s" не найден.', admin_name_to_delete;
    END IF;

    SELECT id_admin INTO new_admin_id FROM administrators WHERE id_admin <> admin_id_to_delete LIMIT 1;

    SELECT name INTO admin_name_to_replace FROM administrators WHERE id_admin = new_admin_id;

    UPDATE theaters SET admin = new_admin_id WHERE admin = admin_id_to_delete;

    INSERT INTO history (change_date, description, previous_admin, new_admin)
    VALUES (CURRENT_DATE, 'Удаление администратора', admin_name_to_delete, admin_name_to_replace);

    DELETE FROM administrators WHERE id_admin = admin_id_to_delete;

    RAISE NOTICE 'Администратор "%s" успешно удален. Данные обновлены.', admin_name_to_delete;
END;
$$ LANGUAGE plpgsql;



-- Вызов процедуры для добавления администратора
CALL add_administrator('Админ 2', '6789', 'emailadmin2@gmail.com');

--

CALL delete_admin('Админ 2');

select * from administrators
select * from theaters
select * from history



create index idx_tickets_price on tickets (price)

-- Регулировать цену билета на сеанс

CREATE OR REPLACE PROCEDURE update_hall_def_price(
    p_hall_name VARCHAR(255),
    p_theater_name VARCHAR(255),
    p_new_def_price NUMERIC(10, 2)
)
security definer
AS $$
DECLARE
    hall_id INTEGER;
    theater_id INTEGER;
BEGIN
    -- Получаем id кинотеатра по его названию
    SELECT id_theater INTO theater_id
    FROM theaters
    WHERE name = p_theater_name;

    -- Проверяем, был ли найден кинотеатр
    IF theater_id IS NULL THEN
        RAISE EXCEPTION 'Кинотеатр с названием "%" не найден.', p_theater_name;
    END IF;

    -- Получаем id зала по его названию и id кинотеатра
    SELECT id_hall INTO hall_id
    FROM halls
    WHERE name = p_hall_name
    AND id_theater = theater_id;

    -- Проверяем, был ли найден зал
    IF hall_id IS NULL THEN
        RAISE EXCEPTION 'Зал с названием "%" в кинотеатре "%" не найден.', p_hall_name, p_theater_name;
    END IF;

    -- Обновляем значение def_price
    UPDATE halls 
    SET def_price = p_new_def_price 
    WHERE id_hall = hall_id 
    AND id_theater = theater_id;

    -- Выводим сообщение об успешном обновлении
    RAISE NOTICE 'Значение def_price для зала "%" в кинотеатре "%" успешно обновлено на %.', p_hall_name, p_theater_name, p_new_def_price;
END;
$$ LANGUAGE plpgsql;

--

CALL update_hall_def_price('Зал 3', 'Кинотеатр 2', 11.00);


select * from halls









-- Возможность поиска билетов на киносеанс по различным параметрам, таким как 
-- название, стоимость, дата показа, жанр, 
-- наличие нужного количества доступных билетов,
-- возможность сортировки фильмов по рейтингу.

--Название

DROP FUNCTION IF EXISTS search_tickets_by_movie_title(character varying);

CREATE OR REPLACE FUNCTION search_tickets_by_movie_title(movie_title_param VARCHAR(255))
RETURNS TABLE (
    movie_title VARCHAR(255),
    hall_name VARCHAR(255),
    session_date JSONB,
    session_time JSONB,
    available_tickets BIGINT
)
security definer
AS $$
DECLARE
    movie_found BOOLEAN;
BEGIN
    movie_found := FALSE;
    
    FOR movie_title, hall_name, session_date, session_time, available_tickets IN
        SELECT i.title AS movie_title,
               h.name AS hall_name,
               TO_JSONB(t.details->>'date') AS session_date,
               TO_JSONB(t.details->>'time') AS session_time,
               COUNT(tk.id_timetable) AS available_tickets
        FROM info_films i
        INNER JOIN timetable t ON i.id_film = t.id_film
        INNER JOIN halls h ON t.id_hall = h.id_hall
        LEFT JOIN tickets tk ON t.id_timetable = tk.id_timetable AND tk.status = 1
        WHERE i.title = movie_title_param
        GROUP BY i.title, h.name, t.details
        ORDER BY h.name
    LOOP
        movie_found := TRUE;
        RETURN NEXT;
    END LOOP;
    
    IF NOT movie_found THEN
        RAISE NOTICE 'Фильм с названием "%" не найден.', movie_title_param;
    END IF;
    
    RETURN;
END;
$$ LANGUAGE plpgsql;

--

SELECT * FROM search_tickets_by_movie_title('Фильм 2');



-- Дата показа

CREATE OR REPLACE FUNCTION search_tickets_by_session_date(session_date_param DATE)
RETURNS TABLE (
    movie_title VARCHAR(255),
    hall_name VARCHAR(255),
    session_date JSONB,
    session_time JSONB,
    available_tickets BIGINT
) 
security definer
AS $$
DECLARE
    movies_found BOOLEAN;
BEGIN
    movies_found := FALSE;

    FOR movie_title, hall_name, session_date, session_time, available_tickets IN
        SELECT i.title AS movie_title,
               h.name AS hall_name,
               TO_JSONB(t.details->>'date') AS session_date,
               TO_JSONB(t.details->>'time') AS session_time,
               COUNT(tk.id_timetable) AS available_tickets
        FROM info_films i
        INNER JOIN timetable t ON i.id_film = t.id_film
        INNER JOIN halls h ON t.id_hall = h.id_hall
        LEFT JOIN tickets tk ON t.id_timetable = tk.id_timetable AND tk.status = 1
        WHERE t.details->>'date' = TO_CHAR(session_date_param, 'YYYY-MM-DD')
        GROUP BY i.title, h.name, t.details
        ORDER BY h.name
    LOOP
        movies_found := TRUE;
        RETURN NEXT;
    END LOOP;

    IF NOT movies_found THEN
        RAISE NOTICE 'На % дату нет фильмов.', TO_CHAR(session_date_param, 'YYYY-MM-DD');
    END IF;

    RETURN;
END;
$$ LANGUAGE plpgsql;

--

SELECT * FROM search_tickets_by_session_date('2024-05-30'::DATE);



-- Жанр

CREATE OR REPLACE FUNCTION search_tickets_by_genre(genre_param VARCHAR(255))
RETURNS TABLE (
    movie_title VARCHAR(255),
    hall_name VARCHAR(255),
    session_date JSONB,
    session_time JSONB,
    available_tickets BIGINT
)
security definer
AS $$
DECLARE
    movies_found BOOLEAN;
BEGIN
    movies_found := FALSE;

    FOR movie_title, hall_name, session_date, session_time, available_tickets IN
        SELECT i.title AS movie_title,
               h.name AS hall_name,
               TO_JSONB(t.details->>'date') AS session_date,
               TO_JSONB(t.details->>'time') AS session_time,
               COUNT(tk.id_timetable) AS available_tickets
        FROM info_films i
        INNER JOIN timetable t ON i.id_film = t.id_film
        INNER JOIN halls h ON t.id_hall = h.id_hall
        LEFT JOIN tickets tk ON t.id_timetable = tk.id_timetable AND tk.status = 1
        WHERE i.genre = genre_params
        GROUP BY i.title, h.name, t.details
        ORDER BY h.name
    LOOP
        movies_found := TRUE;
        RETURN NEXT;
    END LOOP;

    IF NOT movies_found THEN
        RAISE NOTICE 'Фильмов жанра % не найдено.', genre_param;
    END IF;

    RETURN;
END;
$$ LANGUAGE plpgsql;

--

SELECT * FROM search_tickets_by_genre('Жанр 1');



-- Сортировка по рейтингу

drop function sort_films_by_rating()

CREATE OR REPLACE FUNCTION sort_films_by_rating()
RETURNS TABLE (
    movie_title VARCHAR(255),
    genre VARCHAR(255),
    rating FLOAT,
    start_date DATE,
    end_date DATE
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    WITH timetable_dates AS (
        SELECT id_film,
               MIN((details->>'date')::DATE) AS start_date,
               MAX((details->>'date')::DATE) AS end_date
        FROM timetable
        GROUP BY id_film
    )
    SELECT i.title AS movie_title,
           i.genre,
           i.rating,
           td.start_date,
           td.end_date
    FROM info_films i
    INNER JOIN timetable_dates td ON i.id_film = td.id_film
    ORDER BY i.rating DESC;
END;
$$ LANGUAGE plpgsql;


-- вторая версия НЕ ЭТА

drop function sort_films_with_rating()

CREATE OR REPLACE FUNCTION sort_films_with_rating()
RETURNS TABLE (
    movie_title VARCHAR(255),
    film_genre VARCHAR(255),
    film_rating FLOAT
)
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT title AS movie_title,
           i.genre AS film_genre,
           i.rating AS film_rating
    FROM info_films i
    ORDER BY i.rating DESC;
END;
$$ LANGUAGE plpgsql;

-- ЭТА

CREATE OR REPLACE FUNCTION sort_films_with_rating2()
RETURNS TABLE (
    movie_title VARCHAR(255),
    film_genre VARCHAR(255),
    film_rating FLOAT,
    status VARCHAR(20)
)
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT i.title AS movie_title,
           i.genre AS film_genre,
           i.rating AS film_rating,
           CASE
               WHEN EXISTS (
                   SELECT 1 FROM timetable t WHERE t.id_film = i.id_film
               ) THEN 'В прокате'::VARCHAR(20)
               ELSE 'Ожидается в прокате'::VARCHAR(20)
           END AS status
    FROM info_films i
    ORDER BY i.rating DESC;
END;
$$ LANGUAGE plpgsql;


select * from info_films

--
SELECT * FROM sort_films_by_rating();


SELECT * FROM sort_films_with_rating2();


-- По количеству

CREATE OR REPLACE FUNCTION find_tickets_by_quantity(num_tickets_needed INTEGER)
RETURNS TABLE (
    movie_title VARCHAR(255),
    film_genre VARCHAR(255),
    film_rating FLOAT,
    day DATE,
    show_time TIME,
    available_tickets BIGINT 
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
           f.title AS movie_title,
           f.genre AS film_genre,
           f.rating AS film_rating,
           (t.details->>'date')::DATE AS day,
           (t.details->>'time')::TIME AS show_time,
           COUNT(*) AS available_tickets
    FROM timetable t
    INNER JOIN info_films f ON t.id_film = f.id_film
    LEFT JOIN tickets ti ON t.id_timetable = ti.id_timetable
                         AND ti.status = 1
    GROUP BY f.title, f.genre, f.rating, (t.details->>'date')::DATE, (t.details->>'time')::TIME
    HAVING COUNT(*) >= num_tickets_needed;
END;
$$ LANGUAGE plpgsql;


--
SELECT * FROM find_tickets_by_quantity(81);




-- Покупатель может просматривать количество доступных билетов

CREATE OR REPLACE FUNCTION get_available_tickets_summary()
RETURNS TABLE (
    movie_title VARCHAR(255),
    film_genre VARCHAR(255),
    film_rating FLOAT,
    theater_name VARCHAR(255),
    film_status VARCHAR(20),
    total_available_tickets BIGINT
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
           f.title AS movie_title,
           f.genre AS film_genre,
           f.rating AS film_rating,
           th.name AS theater_name,
           CASE
               WHEN EXISTS (SELECT 1 FROM timetable t WHERE t.id_film = f.id_film) THEN 'В прокате'::VARCHAR(20)
               ELSE 'Ожидается в прокате'::VARCHAR(20)
           END AS film_status,
           COALESCE(SUM(CASE WHEN ti.status = 1 THEN 1 ELSE 0 END), 0) AS total_available_tickets
    FROM info_films f
    LEFT JOIN timetable t ON f.id_film = t.id_film
    LEFT JOIN halls h ON t.id_hall = h.id_hall
    LEFT JOIN theaters th ON h.id_theater = th.id_theater
    LEFT JOIN tickets ti ON t.id_timetable = ti.id_timetable
    GROUP BY f.id_film, th.name;
END;
$$ LANGUAGE plpgsql;

--

SELECT * FROM get_available_tickets_summary();

select * from tickets





-- Просмотр стоимости билетов на фильмы

drop function get_tickets_info()

CREATE OR REPLACE FUNCTION get_tickets_info()
RETURNS TABLE (
    movie_title VARCHAR(255),
    film_genre VARCHAR(255),
    film_rating FLOAT,
    available_tickets BIGINT,
    ticket_price_range TEXT
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.title AS movie_title,
        f.genre AS film_genre,
        f.rating AS film_rating,
        COUNT(t.id_row)::BIGINT AS available_tickets,
        (MIN(t.price)::VARCHAR(10) || ' - ' || MAX(t.price)::VARCHAR(10)) AS ticket_price_range
    FROM
        info_films f
    LEFT JOIN
        timetable tt ON f.id_film = tt.id_film
    LEFT JOIN
        tickets t ON tt.id_timetable = t.id_timetable AND t.status = 1
	WHERE
        tt.id_film IS NOT NULL
    GROUP BY
        f.title, f.genre, f.rating;
END;
$$ LANGUAGE plpgsql;

--

select * from get_tickets_info()


-- Поиск по стоимости

drop FUNCTION available_movie_tickets_price(price_range NUMERIC)


CREATE OR REPLACE FUNCTION available_movie_tickets_price(price_range NUMERIC) RETURNS TABLE (
    film_title VARCHAR(255),
    film_rating FLOAT,
    film_genre VARCHAR(255),
    available_tickets BIGINT,
    ticket_price_range JSONB
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.title AS film_title,
        f.rating AS film_rating,
        f.genre AS film_genre,
        COUNT(t.id_row) AS available_tickets,
        jsonb_build_object(
            'min_price', MIN(t.price),
            'max_price', MAX(t.price)
        ) AS ticket_price_range
    FROM
        info_films f
    JOIN
        timetable tt ON f.id_film = tt.id_film
    JOIN
        tickets t ON tt.id_timetable = t.id_timetable
    WHERE
        t.status = 1
    GROUP BY
        f.title, f.rating, f.genre
    HAVING
        COUNT(t.id_row) > 0 -- Считаем количество строк по рандомному полю
        AND MIN(t.price) <= price_range AND MAX(t.price) >= price_range;
END;
$$ LANGUAGE plpgsql;


SELECT * FROM available_movie_tickets_price(13.0);


