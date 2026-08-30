DROP DATABASE IF EXISTS industrial_db;
DROP USER IF EXISTS 'sensor_app'@'%';
CREATE DATABASE industrial_db;
USE industrial_db;
CREATE TABLE festo_telemetry (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    container_id VARCHAR(50),
    station_name VARCHAR(50),
    container_color VARCHAR(20),
    air_pressure_bar FLOAT,
    status VARCHAR(20)
);
CREATE USER 'sensor_app'@'%' IDENTIFIED BY 'SenzorPass123!';
GRANT INSERT, SELECT ON industrial_db.festo_telemetry TO 'sensor_app'@'%';
FLUSH PRIVILEGES;
