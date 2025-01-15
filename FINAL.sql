---------SCRIPT
--Возможность поиска билетов на киносеанс по различным параметрам, 
--таким как название, 
--стоимость, 
--дата показа, 
--жанр, 
--наличие нужного количества доступных билетов, 
--возможность сортировки фильмов по рейтингу.


SELECT * FROM search_tickets_by_movie_title('Фильм 2');

SELECT * FROM search_tickets_by_session_date('2024-05-30'::DATE);

SELECT * FROM search_tickets_by_genre('Жанр 1');

SELECT * FROM sort_films_by_rating();

SELECT * FROM sort_films_with_rating2();

SELECT * FROM find_tickets_by_quantity(81);

SELECT * FROM available_movie_tickets_price(13.0);





---Изменять список фильмов в прокате, регулировать цену билета на сеанс, 
---добавлять, удалять администраторов

CALL add_movie_to_catalog('Крутой фильм', 'Драма', 4.5, 'Описание крутого фильма.');

CALL delete_movie_from_catalog('Крутой фильм');

CALL add_administrator('Админ 4', '6789', 'emailadmin4@gmail.com');

CALL delete_admin('Админ 4');

CALL update_hall_def_price('Зал 1', 'Кинотеатр 2', 11.00);


---Механизм внесения изменений в список, таких как добавление, изменение и удаление сеансов

CALL generate_timetable('Фильм 3', 'Зал 1А', '2024-05-30', '2024-06-30',
                        '[{"time": "10:00", "coefficient": 1.1},
                          {"time": "12:00", "coefficient": 1.5},
                          {"time": "20:00", "coefficient": 1.6}]',
                        'В прокате');
						
CALL delete_movie_from_timetable('Фильм 2', 'Зал 1', 'Кинотеатр 2');

CALL update_timetable_entry('Фильм 2', 'Зал 1', 
                            '2024-05-17', '2024-06-17',
                        '[{"time": "12:00", "coefficient": 1.0},
                          {"time": "18:00", "coefficient": 1.3},
                          {"time": "21:00", "coefficient": 1.6}]',
                            'В прокате');
							
----Добавлять данные о покупателях, рассчитывать итоговую стоимость набора билетов, 
---отмечать количество проданных билетов, изменять количество доступных билетов, 
---отмечать время и дату покупки

SELECT add_customer('aiivqol1@gmail.com');

SELECT * FROM user_ticket_purchases;

SELECT * FROM get_user_ticket_purchases('email3@gmail.com');

SELECT * FROM get_tickets_sold_per_theater();

CALL cancel_ticket('Фильм 2', 'Кинотеатр 2','Зал 1', '2024-05-29', '12:00', 1, 4);


---Просматривать количество доступных билетов, их стоимость, покупать, 
---возвращать билеты, ставить оценку на фильм.

select * from orders
select * from ord_det
select * from timetable
select * from tickets where status = '0'


SELECT * FROM get_available_tickets_summary();


select * from get_tickets_info()

CALL add_rating_by_title('Фильм 3', 'email3@gmail.com', 4.2);

CALL buy_ticket(
    'Фильм 1',       -- Название фильма
    'Кинотеатр 1',   -- Название кинотеатра
    'Зал 1А',         -- Название зала
    '2024-05-15',    -- Дата сеанса
    '12:00',         -- Время сеанса
    1,               -- Номер ряда
    6,               -- Номер места
    'email1@gmail.com'  -- Имя покупателя
);

CALL return_ticket(
    'Фильм 1',       -- Название фильма
    'Кинотеатр 1',   -- Название кинотеатра
    'Зал 1А',         -- Название зала
    '2024-05-15',    -- Дата сеанса
    '12:00',         -- Время сеанса
    1,               -- Номер ряда
    6,               -- Номер места
    'email1@gmail.com'  -- Имя покупателя
);




--- ТЕХНОЛОГИЯ

SELECT *,
       ts_rank(to_tsvector('russian', description), plainto_tsquery('russian', 'Миллиардерами')) AS rank
FROM info_films
WHERE to_tsvector('russian', description) @@ plainto_tsquery('russian', 'Миллиардерами')
ORDER BY rank DESC;


SELECT *,
       ts_rank(to_tsvector('russian', description), websearch_to_tsquery('russian', 'супер фильма')) AS rank
FROM info_films
WHERE to_tsvector('russian', description) @@ websearch_to_tsquery('russian', 'супер фильма')
ORDER BY rank DESC;




----- Для XML -- не нужно

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

-- ЗАРАНЕЕ
select * from temp_theater_movie_tickets


-------------ЭКСПОРТ!


CALL ExportCountTicketsFromTheaterToXML('C:\TheatersTickets.xml');

-------------ИМПОРТ!


CALL ImportFilmsFromXML('C:\info_films.xml');


select * from info_films
select * from ord_det


