-- Создание таблицы "Инфо фильмов"
CREATE TABLE info_films (
  id_film SERIAL PRIMARY KEY,
  title VARCHAR(255) NOT NULL,
  genre VARCHAR(255) NOT NULL,
  rating FLOAT NOT NULL,
  description VARCHAR(2000)
);

-- Создание таблицы "Рейтинг"
CREATE TABLE ratings (
  id_rating SERIAL PRIMARY KEY,
  id_film INTEGER REFERENCES info_films (id_film),
  id_customer INTEGER REFERENCES customers (id_customer),
  rating FLOAT NOT NULL
);

-- Создание таблицы "Список администраторов"
CREATE TABLE administrators (
  id_admin SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  password VARCHAR(255) NOT NULL,
  email VARCHAR(255)
);

select * from theaters
select * from administrators

-- Создание таблицы "Инфо покупателей"
CREATE TABLE customers (
  id_customer SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL
);

-- Создание таблицы "Кинотеатры"
CREATE TABLE theaters (
  id_theater SERIAL PRIMARY KEY,
  name VARCHAR(255) NOT NULL,
  address VARCHAR(255) NOT NULL,
  admin serial REFERENCES administrators (id_admin)
);

-- Создание таблицы "Залы"
CREATE TABLE halls (
  id_hall SERIAL PRIMARY KEY,
  id_theater INTEGER REFERENCES theaters (id_theater),
  name VARCHAR(255) NOT NULL,
  rows integer not null,
  seats integer not null,
  def_price NUMERIC(10, 2) NOT NULL,
  bestrows jsonb,
  bestseats jsonb,
  coefficient NUMERIC(10, 2) not null
);


select * from halls

-- Создание таблицы "Расписание"
CREATE TABLE timetable (
  id_timetable SERIAL PRIMARY KEY,
  id_film INTEGER REFERENCES info_films (id_film),
  id_hall INTEGER REFERENCES halls (id_hall),
  details JSONB, 
  status VARCHAR(20)
);

select * from timetable

-- Создание таблицы "Заказы"
CREATE TABLE orders (
  id_ord SERIAL PRIMARY KEY,
  ord_date DATE,
  id_customer INTEGER REFERENCES customers (id_customer)
);
ALTER TABLE orders
ALTER COLUMN ord_date TYPE TIMESTAMP without time zone;
-- Создание таблицы "Детали заказа (проданные билеты) 2"
CREATE TABLE ord_det (
  id_ord_det SERIAL PRIMARY KEY,
  id_ord INTEGER REFERENCES orders (id_ord),
  id_row INTEGER,
  id_seat INTEGER,
  id_timetable INTEGER REFERENCES timetable (id_timetable),
  FOREIGN KEY (id_row, id_seat, id_timetable) REFERENCES tickets (id_row, id_seat, id_timetable)
);


	-- Создание таблицы "Билеты"
CREATE TABLE tickets (
  id_row SERIAL,
  id_seat SERIAL,
  id_timetable SERIAL REFERENCES timetable (id_timetable),
  price NUMERIC(10, 2),
  status INTEGER CHECK (status IN (0, 1)),
  PRIMARY KEY (id_row, id_seat, id_timetable)
);


CREATE TABLE history (
  id_change SERIAL PRIMARY KEY,
  change_date DATE,
  description VARCHAR(255),
  previous_admin VARCHAR(255),
  new_admin VARCHAR(255)
);


-- VIEW


CREATE VIEW user_ticket_purchases AS
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


--- INSERT'ы

-- Заполнение таблицы "Кинотеатры"
INSERT INTO theaters (name, address, admin)
VALUES
  ('Кинотеатр 1', 'Адрес 1', 1),
  ('Кинотеатр 2', 'Адрес 2', 2),
  ('Кинотеатр 3', 'Адрес 3', 3);

-- Заполнение таблицы "Инфо покупателей"
INSERT INTO customers (name)
VALUES
  ('email1@gmail.com'),
  ('email2@gmail.com'),
  ('email3@gmail.com');
  
INSERT INTO administrators (name, password, email)
VALUES
  ('admin 1', '12345', 'email1@gmail.com'),
  ('admin 2', '11345', 'email2@gmail.com'),
  ('admin 3', '11145', 'email3@gmail.com');

-- Заполнение таблицы "Залы"
INSERT INTO halls (id_theater, name, rows, seats, def_price, bestrows, bestseats, coefficient)
VALUES
  (1, 'Зал 1', 10, 8, 10.50, '[1, 2, 3]', '[4, 5, 6]', 1.1),
  (1, 'Зал 2', 8, 8, 9.00, '[4, 5, 6]', '[4, 5]', 1.1),
  (2, 'Зал 3', 12, 10, 12.00, '[6, 7, 8]', '[4, 5, 6]', 1.2);

select * from info_films

-- Заполнение таблицы "Рейтинг"
INSERT INTO ratings (id_film, id_customer, rating)
VALUES
  (1, 1, 4.5),
  (1, 2, 3.8),
  (2, 1, 4.2);

-- Заполнение таблицы "Инфо фильмов"
INSERT INTO info_films (title, genre, rating, description)
VALUES
  ('Фильуцрщард', 'Жанр 4', 4.2, 'РИОУираилым лкфупрлкрфаоури уаылуапуупршфи вмлркшпршкуфгпршкрпмвыларгушрцфгурп лукпгфрушркуи улапуцшпауимлуи еркурлткылф лгпршфутку муф ае4рфгаруп клкыпркурпку.'),
  ('Фильлудауш', 'Жанр 4', 3.9, 'РИОУираилым лкфупрлкрфаоури уаылуапуупршфи вмлркшпршкуфгпршкрпмвыларгушрцфгурп лукпгфрушркуи улапуцшпауимлуи еркурлткылф лгпршфутку муф ае4рфгаруп клкыпркурпку.'),
  ('Фильмултцадшуо', 'Жанр 4', 4.5, 'РИОУираилым лкфупрлкрфаоури уаылуапуупршфи вмлркшпршкуфгпршкрпмвыларгушрцфгурп лукпгфрушркуи улапуцшпауимлуи еркурлткылф лгпршфутку муф ае4рфгаруп клкыпркурпку.');

select * from info_films

select * from orders
select * from ord_det




