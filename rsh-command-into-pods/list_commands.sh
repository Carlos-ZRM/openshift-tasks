#!/bin/bash

# ===================================================================================
# Script para ejecutar una lista de comandos en todos los pods en ejecución
# y guardar los resultados en un archivo CSV.
#
# Prerrequisitos:
#   - oc (OpenShift CLI) instalado y configurado para acceder a un clúster.
#   - Permisos para 'get' y 'exec' en pods a través de todos los namespaces.
#
# Para ejecutar:
#   1. Guarda este contenido en un archivo (p. ej., pod_runner.sh).
#   2. Dale permisos de ejecución: chmod +x pod_runner.sh
#   3. Ejecútalo: ./pod_runner.sh
# ===================================================================================

# --- CONFIGURACIÓN ---

# Genera una marca de tiempo para nombres de archivo únicos
TIMESTAMP=$(date '+%Y-%m-%d_%H-%M-%S')

# Archivo para guardar los registros de ejecución del script
LOG_FILE="pod_script_${TIMESTAMP}.log"
# Archivo CSV para guardar los resultados de los comandos
CSV_FILE="pod_command_results_${TIMESTAMP}.csv"

# Array con la lista de comandos a ejecutar dentro de cada pod.
# Puedes añadir o quitar comandos de esta lista según tus necesidades.
# Nota: Usa comandos simples y que no requieran interacción.
COMMANDS_TO_RUN=(
    "date"
    "date -u"
    "echo TZ $TZ"
    "rpm -q tzdata"
    "cat /etc/os-release | grep ^ID= | sed 's/ID=//; s/\"//g'"
)

# --- FUNCIONES DE REGISTRO (LOGS) ---

# Función para escribir un mensaje de log con marca de tiempo.
# Esta función ahora escribe SOLAMENTE en el archivo de log, no en la consola.
log_message() {
    local message="$1"
    # Escribe en el archivo de log
    echo "$(date '+%Y-%m-%d %H:%M:%S') [INFO] - $message" >> "$LOG_FILE"
}

# Función para escribir un mensaje de error con marca de tiempo.
# Los errores sí se mostrarán en la consola y en el log.
log_error() {
    local message="$1"
    # Escribe en el archivo de log y en la salida de error estándar (stderr)
    echo "$(date '+%Y-%m-%d %H:%M:%S') [ERROR] - $message" | tee -a "$LOG_FILE" >&2
}


# --- SCRIPT PRINCIPAL ---

# `set -e` asegura que el script se detenga si un comando falla.
# `set -o pipefail` asegura que un pipeline falle si cualquier comando en él falla.
set -e
set -o pipefail

# Limpia el archivo de log de la ejecución actual (ya que es único)
> "$LOG_FILE"
echo "Script iniciado. Generando logs en '$LOG_FILE' y resultados en '$CSV_FILE'..."
log_message "Script iniciado. Los archivos de log y CSV han sido creados con la marca de tiempo: ${TIMESTAMP}"

# Construye la cabecera del CSV dinámicamente
CSV_HEADER="Namespace,Pod"
for cmd in "${COMMANDS_TO_RUN[@]}"; do
    # Reemplaza comas en el comando para no romper el CSV
    clean_cmd=$(echo "$cmd" | sed 's/,/;/g')
    CSV_HEADER="$CSV_HEADER,\"$clean_cmd\""
done

# Escribe la cabecera en el archivo CSV
echo "$CSV_HEADER" > "$CSV_FILE"
log_message "Archivo CSV '$CSV_FILE' creado con la cabecera."
log_message "Comandos a ejecutar en cada pod: ${#COMMANDS_TO_RUN[@]}"

# 1. Obtener una lista de todos los pods en estado 'Running' y filtrar namespaces.
# Formato: namespace nombre-del-pod
log_message "Obteniendo la lista de pods en estado 'Running' y excluyendo namespaces que empiezan con 'openshift' o 'kube'..."
# Se usa grep -vE para invertir la búsqueda y excluir los namespaces del sistema.
pod_list=$(oc get pods --all-namespaces --field-selector=status.phase=Running -o=custom-columns=NAMESPACE:.metadata.namespace,NAME:.metadata.name --no-headers | grep -vE '^(openshift|kube)')

if [ -z "$pod_list" ]; then
    log_error "No se encontraron pods en estado 'Running' que coincidan con los criterios de filtrado. Saliendo del script."
    exit 1
fi

log_message "Se encontraron pods. Empezando el procesamiento..."
echo "Procesando pods..."

# Itera sobre la lista de pods
while read -r namespace pod; do
    if [ -z "$namespace" ] || [ -z "$pod" ]; then
        continue
    fi

    # Salida en la terminal para mostrar el progreso
    echo "  -> Procesando: $namespace/$pod"

    log_message "Procesando Pod: '$pod' en Namespace: '$namespace'"

    # Prepara la fila del CSV con el namespace y el nombre del pod
    CSV_ROW="\"$namespace\",\"$pod\""

    # 2. Ejecutar la lista de comandos en cada pod
    for cmd in "${COMMANDS_TO_RUN[@]}"; do
        log_message "  -> Ejecutando comando: '$cmd'"
        
        # Ejecuta el comando y captura la salida (stdout y stderr)
        # Se utiliza 'sh -c' para asegurar que comandos con pipes o redirecciones funcionen
        command_result=$(oc exec "$pod" -n "$namespace" -- /bin/sh -c "$cmd" 2>&1)
        
        # Verifica el código de salida del comando 'oc exec'
        if [ $? -ne 0 ]; then
            log_error "  -> Fallo al ejecutar comando en el pod '$pod'. Resultado: $command_result"
            # Si el comando falla, se añade un mensaje de error al CSV
            clean_result="COMMAND_FAILED: ${command_result}"
        else
            log_message "  -> Comando ejecutado con éxito."
            clean_result="$command_result"
        fi

        # Limpia el resultado para que sea seguro para el CSV:
        # - Elimina saltos de línea y reemplázalos con un espacio.
        # - Escapa las comillas dobles (reemplazando " por "").
        # - Elimina posibles retornos de carro.
        safe_result=$(echo "$clean_result" | tr -d '\r' | tr '\n' ' ' | sed 's/"/""/g')
        
        # Añade el resultado a la fila del CSV
        CSV_ROW="$CSV_ROW,\"$safe_result\""
    done
    
    # 3. Guarda los resultados en el archivo CSV
    echo "$CSV_ROW" >> "$CSV_FILE"
    log_message "Resultados para el pod '$pod' guardados en el CSV."
    
done <<< "$pod_list" # Redirige la lista de pods al bucle while

log_message "Procesamiento completado."
log_message "Los resultados se han guardado en: $CSV_FILE"
log_message "El registro de ejecución completo está en: $LOG_FILE"

echo ""
echo "¡Ejecución finalizada con éxito!"
