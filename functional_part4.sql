-- Администратор может добавлять данные о покупателях, 
-- рассчитывать итоговую стоимость набора билетов, 
-- отмечать количество проданных билетов, изменять количество доступных билетов, 
-- отмечать время и дату покупки. 

CREATE OR REPLACE FUNCTION add_customer(
    p_customer_name VARCHAR(255)
)
RETURNS VOID
security definer
AS $$
DECLARE
    _existing_customer BOOLEAN;
BEGIN
    -- Проверяем наличие покупателя с таким именем
    SELECT EXISTS(SELECT 1 FROM customers WHERE name = p_customer_name) INTO _existing_customer;

    -- Если покупатель уже существует, выводим сообщение
    IF _existing_customer THEN
        RAISE NOTICE 'Покупатель "%" уже существует.', p_customer_name;
    ELSE
        -- Вставляем данные о покупателе в таблицу customers
        INSERT INTO customers (name) VALUES (p_customer_name);
        
        -- Выводим сообщение об успешном добавлении
        RAISE NOTICE 'Данные о покупателе "%" успешно добавлены в таблицу customers.', p_customer_name;
    END IF;
END;
$$ LANGUAGE plpgsql;

--
select * from customers
select * from orders
select * from ord_det

SELECT add_customer('aiivqol@gmail.com');



--- Рассчитывать итоговую стоимость набора билетов, 

drop view user_ticket_purchases

CREATE or replace VIEW user_ticket_purchases AS
SELECT
    c.name AS user_email,
    o.ord_date AS purchase_date,
    SUM(t.price) AS total_ticket_price
FROM
    orders o
JOIN
    ord_det od ON o.id_ord = od.id_ord
JOIN
    tickets t ON od.id_row = t.id_row AND od.id_seat = t.id_seat AND od.id_timetable = t.id_timetable
JOIN
    customers c ON o.id_customer = c.id_customer
GROUP BY
    c.name, o.ord_date;

---

SELECT * FROM user_ticket_purchases;

-- САМА ФУНКЦИЯ

CREATE OR REPLACE FUNCTION get_user_ticket_purchases(user_name VARCHAR(255))
RETURNS TABLE (
    user_email VARCHAR(255),
    purchase_date TIMESTAMP without time zone,
    total_ticket_price NUMERIC
) 
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
        user_ticket_purchases.user_email,
        user_ticket_purchases.purchase_date,
        user_ticket_purchases.total_ticket_price
    FROM
        user_ticket_purchases
    WHERE
        user_ticket_purchases.user_email = user_name;
END;
$$ LANGUAGE plpgsql;
--

SELECT * FROM get_user_ticket_purchases('email3@gmail.com');



-- Сколько билетов продано по кинотеатрам -- отмечать количество проданных билетов

CREATE OR REPLACE FUNCTION get_tickets_sold_per_theater()
RETURNS TABLE (
    theater_name VARCHAR(255),
    total_tickets_sold INTEGER
)
security definer
AS $$
BEGIN
    RETURN QUERY
    SELECT
        th.name AS theater_name,
        COUNT(*)::INTEGER AS total_tickets_sold
    FROM
        orders o
    JOIN
        ord_det od ON o.id_ord = od.id_ord
    JOIN
        tickets t ON od.id_row = t.id_row AND od.id_seat = t.id_seat AND od.id_timetable = t.id_timetable
    JOIN
        timetable tt ON t.id_timetable = tt.id_timetable
    JOIN
        halls h ON tt.id_hall = h.id_hall
    JOIN
        theaters th ON h.id_theater = th.id_theater
    GROUP BY
        th.name;
END;
$$ LANGUAGE plpgsql;


--

SELECT * FROM get_tickets_sold_per_theater();


--Изменять количество доступных билетов
	
CREATE OR REPLACE PROCEDURE cancel_ticket(
    p_movie_title VARCHAR(255),
    p_theater_name VARCHAR(255),
    p_hall_name VARCHAR(255),
    p_date DATE,
    p_time TIME,
    p_row INTEGER,
    p_seat INTEGER
)
security definer
AS $$
DECLARE
    movie_id INTEGER;
    theater_id INTEGER;
    hall_id INTEGER;
    timetable_id INTEGER;
    ticket_price NUMERIC(10, 2);
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

    -- Обновление статуса билета на "куплен"
    UPDATE tickets 
    SET status = 0 
    WHERE id_row = p_row 
    AND id_seat = p_seat 
    AND id_timetable = timetable_id;

    -- Вывод сообщения о стоимости билета
    RAISE NOTICE 'Билет удален из доступа.';
END;
$$ LANGUAGE plpgsql;



--
select * from tickets where status = 0
select * from timetable
select * from halls
select * from theaters
select * from orders
select * from ord_det

CALL cancel_ticket('Фильм 2', 'Кинотеатр 2','Зал 1', '2024-05-29', '12:00', 1, 3);



--СОЗДАНИЕ РОЛЕЙ

create user manager with password 'qwerty'
grant execute on procedure add_administrator to manager;
grant execute on procedure add_movie_to_catalog to manager;
grant execute on procedure delete_admin to manager;
grant execute on procedure delete_movie_from_catalog to manager;
grant execute on procedure update_hall_def_price to manager;
grant execute on procedure exportcountticketsfromtheatertoxml to manager;
grant execute on procedure generate_timetable to manager;
grant execute on procedure importfilmsfromxml to manager;
grant execute on procedure update_timetable_entry to manager;

create user administrator with password 'qwerty'
grant execute on function add_customer to administrator;
grant execute on function get_user_ticket_purchases to administrator;
grant execute on function get_tickets_sold_per_theater to administrator;
grant execute on procedure cancel_ticket to administrator;

create user customer with password 'qwerty'
grant execute on function available_movie_tickets_price to customer;
grant execute on function find_tickets_by_quantity to customer;
grant execute on function get_available_tickets_summary to customer;
grant execute on function get_tickets_info to customer;
grant execute on function search_tickets_by_genre to customer;
grant execute on function search_tickets_by_movie_title to customer;
grant execute on function search_tickets_by_session_date to customer;
grant execute on function sort_films_by_rating to customer;
grant execute on function sort_films_with_rating2 to customer;
grant execute on procedure buy_ticket to customer;
grant execute on procedure return_ticket to customer;



























