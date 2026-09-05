# Review IIoT — 2026-09-05

Review static al repository-ului Ansible și al integrării dashboard–simulator,
completat cu verificări pe VM-uri și reproduceri locale fără scrieri în DB.
Nu reprezintă un test de reinstalare de la zero sau un audit al AWS Security Groups.

## Modificarea implementată

- site.yml creează maintenance_commands pe master dacă lipsește, cu schema existentă
  în producție. Nu modifică și nu șterge datele tabelei existente.
- Conturi sensor_app specifice IP-urilor: simulatorul are INSERT/SELECT pe telemetrie
  și SELECT/UPDATE pe comenzi; web-serverul are INSERT/SELECT pe comenzi pe master,
  și SELECT pe ambele tabele pe replică.
- Tokenul operatorului și endpointurile DB sunt configurate prin drop-in systemd,
  mod 0600, taskuri cu no_log. Secretul este furnizat separat de Git.
- Restartul Gunicorn se execută prin handler la schimbarea codului/configurației.
- README documentează variabilele Vault și rularea țintită.

## Probleme ordonate după prioritate

1. **P1 — Discul masterului este plin și blochează scrierile.**
   Verificare live: /dev/root 6,8 GB, 100%, 0 disponibili; /var/lib/mysql ~1,7 GB,
   /var/log/mysql ~2,1 GB. Jurnalul MariaDB raportează Errcode 28 la scrierea
   mysql-bin.000003. Ansible nu poate crea directorul temporar.
   roles/db_master/templates/99-replication.cnf.j2:8 activează binlogurile,
   dar repository-ul nu definește retenție, monitorizare spațiu sau arhivare.
   Prioritate: extinderea volumului, apoi dimensionarea retenției în raport cu
   replicarea și backupurile. Nu se șterg manual binloguri active.

2. **P1 — Tokenul de comandă este trimis prin HTTP.**
   roles/web/tasks/main.yml configurează numai listen 80; static/dashboard.js:404
   transmite X-Control-Token. Pe accesul public necriptat, tokenul și comenzile
   nu au protecție TLS. Necesită HTTPS și redirecționare HTTP, cu domeniu/certificat
   sau acces printr-un canal privat securizat.

3. **P1 — Credențiale persistate în cod și conturi wildcard.**
   group_vars/all.yml:4, site.yml (taskurile mysql_user), setup_db.sql:19,
   iiot-web-app/app.py:23 și festo_simulator/main.py:19 conțin parole.
   ansible.cfg:3 dezactivează verificarea identității SSH.
   URL-ul Git din roles/web/tasks/main.yml:31 poate rămâne cu token în .git/config;
   no_log ascunde ieșirea Ansible, nu elimină secretul de pe disc.
   Recomandare: Vault/secret store, rotație coordonată, autentificare Git fără PAT în
   remote și migrare a conturilor wildcard. Noile conturi pe IP nu elimină wildcardurile.

4. **P1 — Replicarea poate rămâne defectă fără să eșueze playbook-ul.**
   roles/db_slave/tasks/main.yml:47,57,64 verifică numai Slave_IO_Running.
   Dacă IO=Yes și SQL=No, toate taskurile de remediere sunt sărite.
   Nu există verificare finală pentru SQL thread, erori, lag sau prezența tabelelor
   înainte de pornirea aplicației. Inițializarea replicii nu include snapshot și
   coordonate/GTID pentru un master care are deja date.
   Recomandare: bootstrap documentat și verificare structurată a ambelor threaduri,
   cu așteptare limitată și eșec explicit.

5. **P1 — Scriptul SQL auxiliar distruge telemetria existentă.**
   setup_db.sql:6 execută DROP TABLE IF EXISTS festo_telemetry;
   linia 20 acordă ALL PRIVILEGES. Nu este apelat de site.yml, dar folosirea lui
   ca script de instalare/resincronizare șterge istoricul.
   Recomandare: migrații fără DROP, iar resetul să fie separat și explicit.

6. **P2 — Mentenanța nu resetează originea uzurii.**
   festo_simulator/main.py:174 resetează scorul, însă maybe_inject_scenario:77
   calculează ținta din timpul global al procesului.
   După expirarea pauzei, modulul revine spre ținta dinaintea intervenției.
   Reproducere locală: la 100h, după reset la 0,04, Bottling are din nou ținta 0,588.
   Recomandare: vârstă/uzură persistentă pe modul și componentă, resetată la intervenție.

7. **P2 — Reumplerea rezervorului se oprește la pragul inferior.**
   festo_simulator/stations/bottling.py:57 intră în reumplere numai sub 1500 ml.
   După depășirea acestui prag, ramura este abandonată, deși rezervorul are 8000 ml.
   Reproducere: pornind de la 1400 ml, după 100 pași de 0,1s rămâne la 1520 ml,
   în IDLE. Recomandare: stare TANK_REFILL menținută până la pragul superior.

8. **P2 — Istoricul mentenanței amestecă ora locală și UTC.**
   site.yml folosește DEFAULT CURRENT_TIMESTAMP(3); common setează Europe/Bucharest.
   app.py:560 nu furnizează created_at; simulator/main.py:197 folosește UTC_TIMESTAMP.
   app.py:521 adaugă Z la ambele. Endpointul live confirmă pentru comanda #1:
   created_at 14:03:05Z și applied_at 11:03:06Z.
   Recomandare: UTC explicit la toate scrierile și migrare controlată a datelor existente.

9. **P2 — Comenzile PROCESSING și starea simulatorului nu sunt recuperabile.**
   simulator/main.py:148 marchează comanda PROCESSING cu autocommit; un crash înainte
   de APPLIED o lasă fără retry, deoarece poll-ul selectează doar PENDING.
   Starea comenzilor active, uzura, WIP și contoarele sunt numai în memorie.
   Scrierea telemetriei la main.py:264 nu are retry protejat; reconectarea ulterioară
   nu ajută dacă execuția a ieșit deja cu excepție.
   Recomandare: checkpoint, lease/timeout pe comenzi și idempotency, retry cu backoff.

10. **P2 — OEE poate număra de două ori opririle.**
    iiot-web-app/app.py:430 calculează debitul pe întreaga durată observată, apoi
    la 440 îl transformă în performanță și la 442 îl multiplică din nou cu
    disponibilitatea. O oprire reduce astfel și A, și P.
    Exemplu conceptual: 50% disponibilitate, viteză nominală când rulează, Q=100%
    produce aproximativ 25%, în loc de 50%.
    Disponibilitatea liniei este min(A_module), care nu descrie reuniunea opririlor
    dacă modulele au opriri la momente diferite.
    Recomandare: durate ale liniei, P raportată la runtime, definiție explicită a
    opririlor planificate și a debitului nominal.

11. **P2 — Telemetria veche poate apărea ca sistem online.**
    static/dashboard.js:510 fixează sfârșitul intervalului la ultima telemetrie,
    iar app.py:444 calculează vechimea față de sfârșitul intervalului.
    Când ingestia se oprește, intervalul se deplasează în trecut și vechimea pare mică.
    UI la dashboard.js:485 declară online dacă există probe.
    Recomandare: separarea stării LIVE (ora curentă, fiecare modul) de datele istorice.

12. **P2 — Filtrarea mentenanței este incompletă.**
    dashboard.js:470 cere doar ultimele 30 de comenzi, indiferent de interval/modul;
    renderMaintenanceHistory:324 filtrează numai contorul intervențiilor în timp,
    nu tabela și nici modulul. Intervențiile mai vechi dispar din total.
    Recomandare: filtre și count în SQL, paginare separată pentru istoric.

13. **P2 — Eșantionarea este folosită și pentru indicatori prezentați ca exacți.**
    app.py:197 păstrează doar ultimul payload din fiecare bucket; la 351/352
    îl folosește ca medie ponderată și vârf. Vârfurile între probe sunt pierdute;
    ritmul mediu de la 383 este media unui contor cumulativ, nu ritmul intervalului.
    Recomandare: agregări exacte pentru medie/maxim și diferențe de contoare pentru ritm;
    eșantionare separată pentru desenarea graficelor.

14. **P2 — Rularea completă nu garantează recuperarea serviciilor.**
    site.yml oprește simulatorul înainte de schema DB, fără bloc always/rescue;
    o eroare poate lăsa deploymentul parțial sau poate continua pe alte hosturi.
    Simulatorul este doar pornit/oprit, nu instalat de acest repository.
    Secretul web este validat târziu, după clonare și alte modificări.
    Recomandare: preflight pentru secrete/spațiu/DB și orchestration cu criterii de
    succes pentru întreaga linie, plus rol de instalare a simulatorului.

15. **P2 — Creștere nelimitată și testare insuficientă.**
    simulator/simulation/models.py:50 păstrează toate recipientele finalizate/deviate
    în memorie; sorting.py:120 și separating.py:114 le adaugă continuu.
    Repository-urile inspectate nu au teste automate pentru aceste fluxuri.
    Nu există retenție a telemetriei în playbook; frecvența nominală este
    5 module la 0,5s (~864.000 rânduri/zi), cu payload JSON și copii în binlog.
    Recomandare: istoric limitat în memorie, retenție/arhivare și teste pe restart,
    DB indisponibil, mentenanță, refill, replicare, intervale și OEE.

## Validare și limite

- Syntax-check Ansible și git diff --check: trecute.
- Compilarea Python a dashboardului și simulatorului: trecută.
- Verificarea JS prin Node nu a rulat: Node nu este instalat.
- Înainte de apariția blocajului de disc, schema și configurația web au fost aplicate;
  rerularea subsetului de atunci a avut changed=0.
- Ultima rulare, cu granturile pe IP: master UNREACHABLE din cauza discului,
  grantul de citire al webului aplicat pe replică, configurația web verificată.
  Granturile noi pe master și idempotenta întregului subset rămân de validat.
- Nu s-au șters date, binloguri sau backupuri pentru a elibera spațiu.
- Reproducerile refill/uzură au rulat în procese locale izolate, fără scrieri în DB.
- Dashboardul este curat local la commit 413e3d6. Nu s-a verificat remote-ul GitHub
  în această reluare.

