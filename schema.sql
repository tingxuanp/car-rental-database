CREATE TABLE IF NOT EXISTS car_make (
  brand     VARCHAR(64),
  model     VARCHAR(64),
  capacity  INT NOT NULL CHECK (capacity > 0),
  PRIMARY KEY (brand, model)
);

CREATE TABLE IF NOT EXISTS car (
  plate       VARCHAR(8) PRIMARY KEY,
  color       VARCHAR(64) NOT NULL,
  brand       VARCHAR(64) NOT NULL,
  model       VARCHAR(64) NOT NULL,
  FOREIGN KEY (brand, model)
    REFERENCES car_make (brand, model)
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY IMMEDIATE
);

CREATE TABLE IF NOT EXISTS customer (
  nric    CHAR(9) PRIMARY KEY,
  name    VARCHAR(256) NOT NULL,
  dob     DATE NOT NULL,
  license BOOLEAN NOT NULL
);

CREATE TABLE IF NOT EXISTS prefer (
  nric    CHAR(9)
    REFERENCES customer (nric)
      ON UPDATE CASCADE
      DEFERRABLE INITIALLY IMMEDIATE,
  brand   VARCHAR(64),
  model   VARCHAR(64),
  FOREIGN KEY (brand, model)
    REFERENCES car_make (brand, model)
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY IMMEDIATE,
  PRIMARY KEY (nric, brand, model)
);

CREATE TABLE IF NOT EXISTS rent (
  nric        CHAR(9) NOT NULL
    REFERENCES customer (nric)
      ON UPDATE CASCADE
      DEFERRABLE INITIALLY IMMEDIATE,
  plate       VARCHAR(8)
    REFERENCES car (plate)
      ON UPDATE CASCADE
      DEFERRABLE INITIALLY IMMEDIATE,
  start_date  DATE,
  end_date    DATE CHECK (end_date >= start_date),
  PRIMARY KEY (plate, start_date, end_date)
);

CREATE TABLE IF NOT EXISTS ride (
  plate       VARCHAR(8),
  start_date  DATE,
  end_date    DATE,
  passenger   CHAR(9) REFERENCES customer (nric)
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY IMMEDIATE,
  FOREIGN KEY (plate, start_date, end_date)
    REFERENCES rent (plate, start_date, end_date)
    ON UPDATE CASCADE
    DEFERRABLE INITIALLY IMMEDIATE,
  PRIMARY KEY (plate, start_date, end_date, passenger)
);


CREATE CONSTRAINT TRIGGER prevent_overlapping_rental
AFTER INSERT OR UPDATE ON rent -- rent table
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_overlap();

-- the same car cannot be rented on two different rent with overlapping dates/ no overlapping start and end date for car rental
-- trigger function 
CREATE OR REPLACE FUNCTION check_overlap()
RETURNS TRIGGER AS $$
DECLARE 
num_overlaps INT;

BEGIN 
SELECT COUNT(plate) INTO num_overlaps
FROM rent
WHERE 
(end_date >= NEW.start_date AND start_date <= NEW.end_date) -- add equality because rental is inclusive of end dates (considered overlapping)
OR 
(start_date >= NEW.start_date AND start_date <= NEW.end_date)

IF num_overlaps > 0 THEN
RAISE EXCEPTION 'There should not be overlapping start and end date for car rental!'
END IF;
END;

-- trigger number 2
CREATE CONSTRAINT TRIGGER prevent_overlapping_customer_ride
BEFORE INSERT OR UPDATE ON ride
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION prevent_overlap_ride()


-- passenger cannot be on two different cars rented with overlapping dates 
CREATE OR REPLACE FUNCTION prevent_overlap_ride()
RETURNS TRIGGER AS $$
DECLARE 
num_overlap INT; -- number of overlapping rides (rentals of the passenger with overlapping dates)
BEGIN
SELECT COUNT(passenger) INTO num_overlap
FROM ride AS r
WHERE r.passenger = NEW.passenger
AND 
(end_date >= NEW.start_date AND start_date <= NEW.end_date) -- add equality because rental is inclusive of end dates (considered overlapping)
OR 
(start_date >= NEW.start_date AND start_date <= NEW.end_date)

IF num_overlap > 0 THEN
RAISE EXCEPTION 'A passenger cannot be on two different cars rented with overlapping dates!'
END IF;
END;


-- trigger number 3 DONE
-- number of passengers must be less than or equal to the capacity of the car 
CREATE OR REPLACE FUNCTION check_capacity()
RETURNS TRIGGER AS $$
DECLARE 
capacity INT; -- capacity of that car 
current_total INT; -- before adding this new passenger to the ride, number of passengers

SELECT cm.capacity INTO capacity
FROM car_make AS cm, car AS c
WHERE car.plate = NEW.plate -- car plate number used to identify the car 
AND c.rband = cm.brand 
AND c.model = cm.model

-- capacity now stores the capacity of the car (an integer)

-- find the current number of passengers already inside this ride (rental)
SELECT COUNT(nric) INTO current_total
FROM ride r
WHERE r.plate = NEW.plate
AND r.start_date = NEW.start_date
AND r.end_date = NEW.end_date -- ensure that it is the same rental by checking against the primary key of rent

IF current_total >= capacity THEN -- if the number of passengers already on this ride >= capacity, then adding one more passenger will cause the capacity to be exceeded 
RETURN NULL -- do not want to insert this new row
ELSE
RETURN NEW; -- else, it is ok to insert this new customer
END IF;
END;


CREATE CONSTRAINT TRIGGER enforce_capacity
BEFORE INSERT OR UPDATE ON ride
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW EXECUTE FUNCTION check_capacity()


-- trigger number 4 DONE
-- deferred trigger 
CREATE CONSTRAINT TRIGGER safe_driving
AFTER INSERT OR UPDATE ON ride -- passengers riding the car
DEFERRABLE INITIALLY DEFERRED -- defer trigger until the end of the transaction
FOR EACH ROW EXECUTE FUNCTION check_driving_license();


CREATE OR REPLACE FUNCTION check_driving_license()
RETURNS TRIGGER AS $$
DECLARE 
num_drivers INT; -- stores number of passengers with a driving license

SELECT COUNT(nric) INTO num_drivers
FROM customer c
WHERE c.nric = NEW.passenger
AND license = TRUE;

IF num_drivers <= 0 THEN 
RAISE EXCEPTION 'One or more of the passengers must have a drivers license!'
END IF;

RETURN NEW;



-- (b) procedures
-- (1) attempts to rent the car to a customer
CREATE OR REPLACE PROCEDURE rent_solo
(IN car VARCHAR(8), IN customer CHAR(9), IN start_date DATE, IN end_date DATE) -- 4 input parameters
AS $$
BEGIN 
INSERT INTO rent VALUES(customer, car, start_date, end_date); -- follow format of insertion
END;
$$ LANGUAGE psql;


-- (2) rent car to the customer, and have exactly 4 passengers riding this car 
CREATE OR REPLACE PROCEDURE rent_group 
(IN car VARCHAR(8), IN customer CHAR(9),
 IN start_date DATE, IN end_date DATE, 
 IN passenger1 CHAR(9), IN passenger2 CHAR(9), 
 IN passenger3 CHAR(9), IN passenger4 CHAR(9))
AS $$
BEGIN
INSERT INTO rent VALUES(customer, car, start_date, end_date);
INSERT INTO ride VALUES(car, start_date, end_date, passenger1);
INSERT INTO ride VALUES(car, start_date, end_date, passenger2);
INSERT INTO ride VALUES(car, start_date, end_date, passenger3);
INSERT INTO ride VALUES(car, start_date, end_date, passenger4);
END;
$$ LANGUAGE psql;
