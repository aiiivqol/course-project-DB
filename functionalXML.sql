-- VIEW с кинотеатрами, фильмами, солд-билетами, MIN/MAX датами
drop VIEW theaters_movie_tickets

CREATE OR REPLACE VIEW theaters_movie_tickets AS
SELECT
    th.name AS theater_name,
    f.title AS movie_title,
    COUNT(od.id_ord_det) AS total_tickets_sold,
    MIN(o.ord_date) AS first_purchase_date,
    MAX(o.ord_date) AS last_purchase_date
FROM
    theaters th
JOIN
    halls h ON th.id_theater = h.id_theater
JOIN
    timetable tt ON h.id_hall = tt.id_hall
JOIN
    info_films f ON tt.id_film = f.id_film
JOIN
    ord_det od ON tt.id_timetable = od.id_timetable
JOIN
    orders o ON od.id_ord = o.id_ord
GROUP BY
    th.name, f.title;


--

select * from theaters_movie_tickets


-- Создание временной таблицы на основе представления и введенных дат
CREATE OR REPLACE FUNCTION get_theater_movie_tickets(theater_name VARCHAR(255), from_date DATE, to_date DATE)
RETURNS VOID 
SECURITY DEFINER
AS $$
BEGIN
    -- Drop the temporary table if it already exists
    IF EXISTS (SELECT 1 FROM pg_tables WHERE tablename = 'temp_theater_movie_tickets') THEN
        DROP TABLE temp_theater_movie_tickets;
    END IF;

    -- Create the temporary table
    CREATE TEMP TABLE temp_theater_movie_tickets AS
    SELECT
        tm.theater_name,
        tm.movie_title,
        tm.total_tickets_sold,
        tm.first_purchase_date,
        tm.last_purchase_date
    FROM
        theaters_movie_tickets tm
    WHERE
        tm.theater_name = get_theater_movie_tickets.theater_name
        AND tm.first_purchase_date >= get_theater_movie_tickets.from_date
        AND tm.last_purchase_date <= get_theater_movie_tickets.to_date;
END;
$$ LANGUAGE plpgsql;


--

SELECT get_theater_movie_tickets('Кинотеатр 2', '2024-05-15', '2024-05-18');
--
delete from temp_theater_movie_tickets
select * from temp_theater_movie_tickets




-- ЭКСПОРТ В XML

CREATE OR REPLACE PROCEDURE ExportCountTicketsFromTheaterToXML(
    file_path TEXT
) 
security definer
AS $$
DECLARE
    xml_data TEXT := '<?xml version="1.0" encoding="UTF-8"?><TheatersTickets>';
    theater_movie_ticket_rec RECORD;
BEGIN
    FOR theater_movie_ticket_rec IN SELECT * FROM temp_theater_movie_tickets LOOP
        xml_data := xml_data || '<theater_movie_ticket>';
        xml_data := xml_data || '<theater_name>' || theater_movie_ticket_rec.theater_name || '</theater_name>';
        xml_data := xml_data || '<movie_title>' || theater_movie_ticket_rec.movie_title || '</movie_title>';
        xml_data := xml_data || '<total_tickets_sold>' || theater_movie_ticket_rec.total_tickets_sold || '</total_tickets_sold>';
        xml_data := xml_data || '<from_date>' || theater_movie_ticket_rec.first_purchase_date || '</from_date>';
        xml_data := xml_data || '<to_date>' || theater_movie_ticket_rec.last_purchase_date || '</to_date>';
        xml_data := xml_data || '</theater_movie_ticket>';
    END LOOP;

    xml_data := xml_data || '</TheaterTickets>';

    EXECUTE format('COPY (SELECT %L) TO %L', xml_data, file_path);

    RAISE NOTICE 'Данные успешно загружены в XML файл: %', file_path;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Ошибка при экспортировке данных в XML: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;


CALL ExportCountTicketsFromTheaterToXML('C:\TheatersTickets.xml');

select * from info_films


-- Из XML в БД

CREATE OR REPLACE PROCEDURE ImportFilmsFromXML(file_path VARCHAR) 
security definer
AS $$
DECLARE
    xml_data TEXT;
BEGIN
    -- Read data from the file
    xml_data := pg_read_file(file_path);

    -- Check if data is read successfully
    IF xml_data IS NULL THEN
        RAISE EXCEPTION 'Failed to read data from file %', file_path;
    END IF;

    -- Display the data read from the file for debugging
    RAISE INFO 'Данные проверяются из файла: %', xml_data;

    -- Create a temporary table for importing data
    CREATE TEMP TABLE tmp_films (
        title VARCHAR(255),
        genre VARCHAR(255),
        rating INT,
		description VARCHAR(2000)
    );

    -- Insert new data from XML into the temporary table
    BEGIN
        EXECUTE 'INSERT INTO tmp_films (title, genre, rating, description)
            SELECT 
                unnest(xpath(''/info_films/info_films/title/text()'',
                    xmlparse(document ''' || xml_data || ''')))::text AS title,
                unnest(xpath(''/info_films/info_films/genre/text()'',
                    xmlparse(document ''' || xml_data || ''')))::text AS genre,
                CAST(TRIM(unnest(xpath(''/info_films/info_films/rating/text()'',
                    xmlparse(document ''' || xml_data || ''')))::text) AS INT) AS rating,
				unnest(xpath(''/info_films/info_films/description/text()'',
                    xmlparse(document ''' || xml_data || ''')))::text AS description';
    EXCEPTION
        WHEN OTHERS THEN
            RAISE EXCEPTION 'Возникла ошибка с импортом данных из XML: %', SQLERRM;
    END;

    -- Insert data from the temporary table into info_films
    INSERT INTO info_films (title, genre, rating, description)
    SELECT title, genre, rating, description FROM tmp_films;

    RAISE INFO 'Данный каталог был успешно перенесен из файла % во временную таблицу tmp_films', file_path;
END;
$$ LANGUAGE plpgsql;

--

CALL ImportFilmsFromXML('C:\info_films.xml');

--

select * from tmp_films
select * from info_films
select * from ord_det






-- FULL-TEXT-SEARCH НЕ РАБОТАЕТ!
drop index idx_info_films_text_search
drop function GetFilteredFilms

CREATE INDEX idx_info_films_text_search ON info_films USING GIN(to_tsvector('russian', title || ' ' || description));

CREATE OR REPLACE FUNCTION GetFilteredFilms(
    search_query VARCHAR(255) DEFAULT NULL,
    genre_filter VARCHAR(255) DEFAULT NULL,
    rating_filter FLOAT DEFAULT NULL,
    sort_by_rating VARCHAR(10) DEFAULT NULL,
    sort_by_title VARCHAR(10) DEFAULT NULL
)
RETURNS TABLE (
    film_id INT,
    title VARCHAR(255),
    genre VARCHAR(255),
    rating FLOAT,
    description VARCHAR(2000)
)
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
        f.id_film,
        f.title,
        f.genre,
        f.rating,
        f.description
    FROM
        info_films f
    WHERE
        (to_tsvector('russian', f.title || ' ' || f.description) @@ plainto_tsquery('russian', search_query) OR f.title ILIKE '%' || search_query || '%' OR f.description ILIKE '%' || search_query || '%' OR search_query IS NULL)
        AND (f.genre ILIKE '%' || genre_filter || '%' OR genre_filter IS NULL)
        AND (f.rating = rating_filter OR rating_filter IS NULL)
    ORDER BY
        CASE WHEN sort_by_rating = 'asc' THEN f.rating END ASC,
        CASE WHEN sort_by_rating = 'desc' THEN f.rating END DESC,
        CASE WHEN sort_by_title = 'asc' THEN f.title END ASC,
        CASE WHEN sort_by_title = 'desc' THEN f.title END DESC;
END;
$$ LANGUAGE plpgsql;

--

SELECT * FROM GetFilteredFilms('тони', NULL, NULL, NULL, 'asc');
-- пару запросов напр по тексту дескрип 
-- синтаксис с операторами,
select * from info_films





--- как хотела Блинова

CREATE INDEX idx_description_fts 
ON info_films 
USING gin(to_tsvector('russian', description));


-- поиск по словосочетанию и между ними слова если есть

SELECT *,
       ts_rank(to_tsvector('russian', description), websearch_to_tsquery('russian', 'супер фильма')) AS rank
FROM info_films
WHERE to_tsvector('russian', description) @@ websearch_to_tsquery('russian', 'супер фильма')
ORDER BY rank DESC;




-- работает поиск по формам различным

SELECT *,
       ts_rank(to_tsvector('russian', description), plainto_tsquery('russian', 'Миллиардеры')) AS rank
FROM info_films
WHERE to_tsvector('russian', description) @@ plainto_tsquery('russian', 'Миллиардеры')
ORDER BY rank DESC;

create extension if not exists pg_trgm
create extension if not exists unaccent 



















---- 100 000 строк в тестовую таблицу

CREATE OR REPLACE FUNCTION fill_customer_table()
RETURNS VOID AS $$
DECLARE
    i INT := 1;
BEGIN
    WHILE i <= 100000 LOOP
        INSERT INTO customers_test (name) VALUES ('Customer' || i);
        i := i + 1;
    END LOOP;
END;
$$ LANGUAGE plpgsql;


SELECT fill_customer_table();

select * from customers_test

