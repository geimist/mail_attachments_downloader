#!/bin/bash
# Mail attachement downloader
# /volume3/DEV/get_mail_attachments.sh
# Python library: https://github.com/jamesridgway/attachment-downloader

# ACHTUNG: Alle Dateien, die nicht einer Dateierweiterung in $file_extensions_user entspricht, werden gelöscht, 
# da attachment-downloader zunächst alle Mailanhänge herunter lädt

# lokales Zielverzeichnis:
DOWNLOAD_FOLDER="/volume3/synOCR/input"

# Gewünschte Dateiendungen definieren (Groß- und Kleinschreibung wird ignoriert - Beispiel: ("jpg" "png" "pdf") ):
file_extensions_user=("pdf")

# IMAP Host:
HOST=""

# IMAP Username:
USERNAME=""

# IMAP Password:
PASSWORD=""

# IMAP Folder to extract attachments from:
IMAP_FOLDER="inbox"

# --------------------- optionale Parameter --------------------
# Regex, mit der der Betreff übereinstimmen muss:
SUBJECT_REGEX=""

# Startzeitpunkt für die Suche (Weltzeit!):
# leer lassen, um keine Limit in der Vergangenheit zu setzen
# wird am Ende des Skriptes auf die aktuelle Zeit gesetzt um beim erneuten Aufruf als Startzeit zu dienen
# z.B. "2021-02-06T13:00:00"
#DATE_AFTER="2023-08-01T17:40:48"
DATE_AFTER=""

# Endzeitpunkt für die Suche (Weltzeit!):
# leer lassen, um alle Mails bis 'JETZT' zu berücksichtigen
# z.B. "2021-02-06T13:25:00"
DATE_BEFORE=""

# Vorlage für Dateinamen (jinja2):
# z.B. "{{date}}/{{ message_id }}/{{ subject }}/{{ attachment_name }}"
FILENAME_TEMPLATE=""

# heruntergeladene Mails löschen (true / false)
DELETE="false"

# IMAP Ordner, um Mails vor dem Löschen zu kopieren:
DELETE_COPY_FOLDER=""

# speziellen imap server port verwenden (defaults to 993 for TLS and 143 otherwise)
PORT=""

# keine verschlüsselte Verbindung verwenden (nicht empfohlen) (true / false)
UNSECURE=""

# verwende STARTTLS (nicht empfohlen) (true / false)
STARTTLS=""


# ab hier nichts mehr ändern
# ##############################################################
# Startzeit speichern:
# --------------------------------------------------------------
start_datetime=$(date +'%Y-%m-%dT%H:%M:%S')
start_datetime_utc=$(date -u +'%Y-%m-%dT%H:%M:%S')

# prüfe Variablen:
# --------------------------------------------------------------
[ ! -d "${DOWNLOAD_FOLDER}" ] && echo "! ! ! ERROR - Zielverzeichnis ist ungülgig!" && exit 1
[ -z "${HOST}" ] && echo "! ! ! ERROR - kein Server (HOST) definiert." && exit 1
[ -z "${USERNAME}" ] && echo "! ! ! ERROR - kein Benutzername (USERNAME) definiert." && exit 1
[ -z "${PASSWORD}" ] && echo "! ! ! ERROR - kein Passwort (PASSWORD) definiert." && exit 1

# stelle Kommando zusammen:
# --------------------------------------------------------------
cmd="--host=${HOST} --username=\"${USERNAME}\" --password=${PASSWORD}"
[ -n "${IMAP_FOLDER}" ] && cmd="${cmd} --imap-folder=${IMAP_FOLDER}"
[ -n "${SUBJECT_REGEX}" ] && cmd="${cmd} --subject-regex=${SUBJECT_REGEX}"
[ -n "${DATE_AFTER}" ] && cmd="${cmd} --date-after=${DATE_AFTER}"
[ -n "${DATE_BEFORE}" ] && cmd="${cmd} --date-before=${DATE_BEFORE}"
[ -n "${FILENAME_TEMPLATE}" ] && cmd="${cmd} --filename-template=${FILENAME_TEMPLATE}"
if [ -n "${DELETE}" ] && [ "${DELETE}" = true ]; then
    cmd="${cmd} --delete"
    [ -n "${DELETE_COPY_FOLDER}" ] && cmd="${cmd} --delete-copy-folder=${DELETE_COPY_FOLDER}"
fi
[ -n "${PORT}" ] && cmd="${cmd} --port=${PORT}"
[ -n "${UNSECURE}" ] && [ "${UNSECURE}" = true ] && cmd="${cmd} --unsecure"
[ -n "${STARTTLS}" ] && [ "${STARTTLS}" = true ] && cmd="${cmd} --starttls"
cmd="${cmd} --output=${DOWNLOAD_FOLDER}"

echo "Kommando: attachment-downloader ${cmd}"

# ##############################################################
# erstelle python environment:
# --------------------------------------------------------------
echo "➜ check Pythonumgebung …"
python_module_list=( attachment-downloader )
my_name="${0##*/}"
my_path="${0%/*}"
python_env_path="${my_path}/${my_name%.*}_pyEnv"

if [ ! -d "${python_env_path}" ]; then
    python3 -m venv "${python_env_path}"
    source "${python_env_path}/bin/activate"
else
    source "${python_env_path}/bin/activate"
fi

if ! python3 -m pip --version > /dev/null  2>&1 ; then
    # Python3 pip was not found and will be now installed:
    # install pip:
    python3 -m ensurepip --default-pip
    # upgrade pip:
    python3 -m pip install --upgrade pip
fi

if python3 -m pip list 2>&1 | grep -q "version.*is available" ; then
    printf "%s\n" "${log_indent}  pip already installed ($(python3 -m pip --version)) / upgrade available ..."
    python3 -m pip install --upgrade pip | sed -e "s/^/${log_indent}  /g"
fi

# check / install python modules:
echo "➜ check Pythonmodule …"
moduleList=$(python3 -m pip list 2>/dev/null)

for module in "${python_module_list[@]}"; do
    moduleName=$(echo "${module}" | awk -F'=' '{print $1}' )

    unset tmp_log1
    printf "%s" "➜ check python module \"${module}\": ➜ "
    if !  grep -qi "${moduleName}" <<<"${moduleList}"; then
        printf "%s" "${module} was not found and will be installed ➜ "

        # install module:
        tmp_log1=$(python3 -m pip install "${module}")

        # check install:
        if grep -qi "${moduleName}" <<<"$(python3 -m pip list 2>/dev/null)" ; then
            echo "ok"
        else
            echo "failed ! ! ! (please install ${module} manually)"
            echo "install log:" && echo "${tmp_log1}"
            return 1
        fi
    else
        printf "ok\n"
    fi
done


# ##############################################################
# run attachment-downloader
# ---------------------------------------------------------------------
echo "➜ Mailanhänge laden …"
eval "attachment-downloader ${cmd}"

echo "➜ setze \"DATE_AFTER\" auf Startzeit des aktuellen Aufrufs (UTC) …"
sed -i 's~^'DATE_AFTER'=.*~'DATE_AFTER'=\"'${start_datetime_utc}'\"~' "${0}"

echo "➜ lösche unerwünschte Dateien …"

# Konvertieren der eingegebenen Dateiendungen in eine reguläre Ausdruckssyntax (Groß- und Kleinschreibung ignorieren)
file_extensions_regex=""
for ext in "${file_extensions_user[@]}"; do
    file_extensions_regex+="\|$(echo "$ext" | tr '[:upper:]' '[:lower:]')"
    file_extensions_regex+="\|$(echo "$ext" | tr '[:lower:]' '[:upper:]')"
done
file_extensions_regex="\(${file_extensions_regex:2}\)" # Entferne das führende "|" und ergänze Klammer

# Löschen aller anderen Dateien im aktuellen Verzeichnis
find "${DOWNLOAD_FOLDER}" -maxdepth 1 -type f ! -regex ".*\.${file_extensions_regex}$" -newermt "${start_datetime}" -exec rm -f {} \;


echo "done :-)"
