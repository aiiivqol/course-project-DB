-- Покупатель может ставить оценку на фильм

-- Создание функции триггера для обновления среднего рейтинга в info_films
CREATE OR REPLACE FUNCTION update_average_rating()
RETURNS TRIGGER AS $$
BEGIN
  UPDATE info_films AS f
  SET rating = (
    SELECT AVG(rating)
    FROM ratings
    WHERE id_film = NEW.id_film
  )
  WHERE f.id_film = NEW.id_film;
  RETURN NEW;
END;
$$ LANGUAGE plpgsql;



-- Создание триггера после вставки рейтинга в ratings
CREATE TRIGGER update_rating_trigger
AFTER INSERT ON ratings
FOR EACH ROW
EXECUTE FUNCTION update_average_rating();

select * from info_films

-- Создание самой процедуры


CREATE OR REPLACE PROCEDURE add_rating_by_title(
    film_title VARCHAR(255),
    user_name VARCHAR(255),
    user_rating FLOAT
)
AS $$
DECLARE
    film_id INTEGER;
    user_id INTEGER;
BEGIN
    -- Получаем идентификатор фильма по его названию
    SELECT id_film INTO film_id FROM info_films WHERE title = film_title;

    -- Получаем идентификатор пользователя по его имени
    SELECT id_customer INTO user_id FROM customers WHERE name = user_name;

    -- Проверяем, существует ли пользователь и фильм
    IF film_id IS NULL THEN
        RAISE EXCEPTION 'Фильм с названием "%", указанным в параметрах, не найден в базе данных.', film_title;
    END IF;

    IF user_id IS NULL THEN
        RAISE EXCEPTION 'Пользователь с именем "%", указанным в параметрах, не найден в базе данных.', user_name;
    END IF;

    -- Проверяем, существует ли уже рейтинг для этого фильма от этого пользователя
    IF EXISTS (SELECT 1 FROM ratings WHERE id_film = film_id AND id_customer = user_id) THEN
        RAISE EXCEPTION 'Рейтинг для фильма "%", уже существует от пользователя "%".', film_title, user_name;
    END IF;

    -- Добавляем рейтинг в таблицу ratings
    INSERT INTO ratings (id_film, id_customer, rating) VALUES (film_id, user_id, user_rating);

    RAISE NOTICE 'Рейтинг для фильма "%", добавлен успешно.', film_title;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'Ошибка: %', SQLERRM;
END;
$$ LANGUAGE plpgsql;

--

CALL add_rating_by_title('Фильм 3', 'email1@gmail.com', 4.2);

select * from ratings
select * from info_films



-- Покупка билета

CREATE OR REPLACE PROCEDURE buy_ticket(
    p_movie_title VARCHAR(255),
    p_theater_name VARCHAR(255),
    p_hall_name VARCHAR(255),
    p_date DATE,
    p_time TIME,
    p_row INTEGER,
    p_seat INTEGER,
    p_customer_name VARCHAR(255)
)
AS $$
DECLARE
    movie_id INTEGER;
    theater_id INTEGER;
    hall_id INTEGER;
    timetable_id INTEGER;
    ticket_price NUMERIC(10, 2);
    customer_id INTEGER;
    order_id INTEGER;
BEGIN
    -- Проверка доступности билета
    SELECT t.id_timetable, tk.price
    INTO timetable_id, ticket_price
    FROM timetable t
    JOIN halls h ON t.id_hall = h.id_hall
    JOIN theaters th ON h.id_theater = th.id_theater
    JOIN info_films f ON t.id_film = f.id_film
    JOIN tickets tk ON tk.id_timetable = t.id_timetable
    WHERE f.title = p_movie_title
    AND th.name = p_theater_name
    AND h.name = p_hall_name
    AND t.details->>'date' = to_char(p_date, 'YYYY-MM-DD')
    AND t.details->>'time' = to_char(p_time, 'HH24:MI')
    AND tk.id_row = p_row
    AND tk.id_seat = p_seat
    AND tk.status = 1;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Билет на указанный фильм, кинотеатр, зал, дату, время, ряд и место недоступен или не существует.';
    END IF;

    -- Получение ID покупателя
    SELECT id_customer INTO customer_id FROM customers WHERE name = p_customer_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Покупатель с именем "%", указанным в параметрах, не найден в базе данных.', p_customer_name;
    END IF;

    -- Создание заказа
    INSERT INTO orders (ord_date, id_customer) 
    VALUES (CURRENT_DATE, customer_id) 
    RETURNING id_ord INTO order_id;
    
    -- Создание записи о купленном билете
    INSERT INTO ord_det (id_ord, id_row, id_seat, id_timetable) 
    VALUES (order_id, p_row, p_seat, timetable_id);
    
    -- Обновление статуса билета на "куплен"
    UPDATE tickets 
    SET status = 0 
    WHERE id_row = p_row 
    AND id_seat = p_seat 
    AND id_timetable = timetable_id;

    -- Вывод сообщения о стоимости билета
    RAISE NOTICE 'Билет куплен. Стоимость: %', ticket_price;
END;
$$ LANGUAGE plpgsql;


--
select * from timetable
select * from orders
select * from ord_det

CALL buy_ticket(
    'Фильм 2',       -- Название фильма
    'Кинотеатр 2',   -- Название кинотеатра
    'Зал 1',         -- Название зала
    '2024-05-15',    -- Дата сеанса
    '12:00',         -- Время сеанса
    1,               -- Номер ряда
    2,               -- Номер места
    'email3@gmail.com'  -- Имя покупателя
);


select * from timetable
select * from tickets where status = '0'
select * from orders
select * from ord_det



-- Возврат билета

CREATE OR REPLACE PROCEDURE return_ticket(
    p_movie_title VARCHAR(255),
    p_theater_name VARCHAR(255),
    p_hall_name VARCHAR(255),
    p_date DATE,
    p_time TIME,
    p_row INTEGER,
    p_seat INTEGER,
    p_customer_name VARCHAR(255)
)
security definer
AS $$
DECLARE
    _customer_id INTEGER;
    _ticket_id_row INTEGER;
    _ticket_id_seat INTEGER;
    _ticket_id_timetable INTEGER;
    _ticket_price NUMERIC(10, 2);
    _order_id INTEGER;
BEGIN
    -- Получаем ID покупателя
    SELECT id_customer INTO _customer_id FROM customers WHERE name = p_customer_name;
    IF NOT FOUND THEN
        RAISE EXCEPTION 'Покупатель с именем "%" не найден в базе данных.', p_customer_name;
    END IF;

    -- Получаем информацию о билете
    SELECT tk.id_row, tk.id_seat, tk.id_timetable, tk.price, o.id_ord
    INTO _ticket_id_row, _ticket_id_seat, _ticket_id_timetable, _ticket_price, _order_id
    FROM tickets tk
    JOIN ord_det od ON tk.id_row = od.id_row AND tk.id_seat = od.id_seat AND tk.id_timetable = od.id_timetable
    JOIN orders o ON od.id_ord = o.id_ord
    JOIN timetable t ON tk.id_timetable = t.id_timetable
    JOIN halls h ON t.id_hall = h.id_hall
    JOIN theaters th ON h.id_theater = th.id_theater
    JOIN info_films f ON t.id_film = f.id_film
    WHERE f.title = p_movie_title
        AND th.name = p_theater_name
        AND h.name = p_hall_name
        AND t.details->>'date' = to_char(p_date, 'YYYY-MM-DD')
        AND t.details->>'time' = to_char(p_time, 'HH24:MI')
        AND tk.id_row = p_row
        AND tk.id_seat = p_seat;

    IF NOT FOUND THEN
        RAISE EXCEPTION 'Билет на указанный фильм, кинотеатр, зал, дату, время, ряд и место недоступен или не существует.';
    END IF;

    -- Проверяем, был ли билет куплен данным пользователем
    IF NOT EXISTS (
        SELECT 1
        FROM ord_det od
        JOIN orders o ON od.id_ord = o.id_ord
        WHERE od.id_row = _ticket_id_row 
        AND od.id_seat = _ticket_id_seat 
        AND od.id_timetable = _ticket_id_timetable
        AND o.id_customer = _customer_id
    ) THEN
        RAISE EXCEPTION 'Билет не может быть возвращен, так как он зарегестрирован не на Вас.';
    END IF;

    -- Удаляем запись о билете из таблицы ord_det
    DELETE FROM ord_det 
    WHERE id_row = _ticket_id_row 
    AND id_seat = _ticket_id_seat 
    AND id_timetable = _ticket_id_timetable;

    -- Обновляем статус билета на доступный
    UPDATE tickets 
    SET status = 1 
    WHERE id_row = _ticket_id_row 
    AND id_seat = _ticket_id_seat 
    AND id_timetable = _ticket_id_timetable;

    -- Удаляем заказ
    DELETE FROM orders WHERE id_ord = _order_id;

    -- Выводим сообщение о стоимости билета
    RAISE NOTICE 'Билет успешно возвращен. Вам возвращено % рублей.', _ticket_price;
END;
$$ LANGUAGE plpgsql;



-- ОНО РАБОТАЕТ!

select * from orders
select * from ord_det

CALL return_ticket(
    'Фильм 2',       -- Название фильма
    'Кинотеатр 2',   -- Название кинотеатра
    'Зал 1А',         -- Название зала
    '2024-05-15',    -- Дата сеанса
    '09:00',         -- Время сеанса
    3,               -- Номер ряда
    6,               -- Номер места
    'Покупатель 2'  -- Имя покупателя
);


