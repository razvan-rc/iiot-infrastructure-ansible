-- Crearea bazei de date (daca nu exista)
CREATE DATABASE IF NOT EXISTS industrial_db;
USE industrial_db;

-- Daca exista varianta veche a tabelului, o stergem pentru a face loc noii arhitecturi
DROP TABLE IF EXISTS festo_telemetry;

-- Crearea tabelului pentru Digital Twin (JSON)
CREATE TABLE festo_telemetry (
    id INT AUTO_INCREMENT PRIMARY KEY,
    timestamp DATETIME(3) DEFAULT CURRENT_TIMESTAMP(3),
    station_name VARCHAR(50) NOT NULL,
    payload_json JSON NOT NULL,
    INDEX idx_station (station_name),
    INDEX idx_timestamp (timestamp)
);

-- Securitate: User-ul de aplicatie
CREATE USER IF NOT EXISTS 'sensor_app'@'%' IDENTIFIED BY 'SenzorPass123!';
GRANT ALL PRIVILEGES ON industrial_db.* TO 'sensor_app'@'%';
FLUSH PRIVILEGES;
