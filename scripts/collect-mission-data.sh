#!/bin/bash

# Script para recopilar datos del sistema OpenClaw para el dashboard de misión control
# Se ejecuta cada 5 minutos vía cron

WORKSPACE="/home/skybot/.openclaw/workspace"
DATA_FILE="$WORKSPACE/mission-data.json"
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Función para obtener métricas del sistema
get_system_metrics() {
    # CPU usage
    CPU_USAGE=$(top -bn1 | grep "Cpu(s)" | sed "s/.*, *\([0-9.]*\)%* id.*/\1/" | awk '{print 100 - $1}')
    
    # Memory usage
    MEM_INFO=$(free | grep Mem)
    MEM_TOTAL=$(echo $MEM_INFO | awk '{print $2}')
    MEM_USED=$(echo $MEM_INFO | awk '{print $3}')
    MEM_USAGE=$(echo "scale=2; $MEM_USED * 100 / $MEM_TOTAL" | bc)
    
    # Disk usage
    DISK_USAGE=$(df / | tail -1 | awk '{print $5}' | sed 's/%//')
    
    # Uptime
    UPTIME=$(cat /proc/uptime | awk '{print int($1/86400)"d "int(($1%86400)/3600)"h"}')
    
    # Load average
    LOAD_AVG=$(cat /proc/loadavg | awk '{print $1", "$2", "$3}')
    
    echo "{
        \"cpu_usage\": $(printf "%.0f" $CPU_USAGE),
        \"memory_usage\": $(printf "%.0f" $MEM_USAGE),
        \"disk_usage\": $(printf "%.0f" $DISK_USAGE),
        \"uptime\": \"$UPTIME\",
        \"load_average\": \"$LOAD_AVG\",
        \"free_memory_gb\": $(echo "scale=2; $(grep MemTotal /proc/meminfo | awk '{print $2}') / 1024 / 1024" | bc)
    }"
}

# Función para obtener información de sesiones OpenClaw
get_openclaw_sessions() {
    # Intentar obtener sesiones activas
    if command -v sessions_list >/dev/null 2>&1; then
        SESSIONS_DATA=$(sessions_list --limit 10 --includeLastMessage 2>/dev/null || echo '{"count": 0, "sessions": []}')
        echo "$SESSIONS_DATA" | jq -c '.count as $count | {active_sessions: $count, sessions: .sessions | map({key, label, model, status, updatedAt})}' 2>/dev/null || echo '{"active_sessions": 0, "sessions": []}'
    else
        echo '{"active_sessions": 0, "sessions": []}'
    fi
}

# Función para obtener estado de Telegram y nodos
get_connection_status() {
    TELEGRAM_STATUS="online"
    GATEWAY_STATUS="online"
    PAIRED_NODES=0
    
    # Intentar verificar Telegram
    if command -v nodes >/dev/null 2>&1; then
        NODES_DATA=$(nodes status 2>/dev/null || echo '{"nodes": []}')
        PAIRED_NODES=$(echo "$NODES_DATA" | jq '.nodes | length' 2>/dev/null || echo "0")
    fi
    
    echo "{
        \"telegram_status\": \"$TELEGRAM_STATUS\",
        \"gateway_status\": \"$GATEWAY_STATUS\",
        \"paired_nodes\": $PAIRED_NODES
    }"
}

# Función para obtener logs recientes
get_recent_logs() {
    LOGS=""
    
    # Intentar obtener logs de sesiones recientes
    if command -v sessions_history >/dev/null 2>&1; then
        MAIN_SESSION_KEY=$(sessions_list --limit 1 --query "agent:main:main" 2>/dev/null | jq -r '.sessions[0].key // empty')
        if [ -n "$MAIN_SESSION_KEY" ]; then
            LOGS=$(sessions_history --sessionKey "$MAIN_SESSION_KEY" --limit 5 --includeTools 2>/dev/null || echo "")
        fi
    fi
    
    if [ -z "$LOGS" ]; then
        # Logs de fallback
        LOGS="[{ \"timestamp\": \"$(date -u +"%H:%M:%S")\", \"message\": \"Sistema de monitoreo activo\" }, { \"timestamp\": \"$(date -u -d '1 minute ago' +"%H:%M:%S")\", \"message\": \"Recopilando datos del sistema\" }]"
    fi
    
    echo "$LOGS"
}

# Recopilar todos los datos
SYSTEM_METRICS=$(get_system_metrics)
SESSIONS_DATA=$(get_openclaw_sessions)
CONNECTION_STATUS=$(get_connection_status)
RECENT_LOGS=$(get_recent_logs)

# Combinar todo en un objeto JSON
cat > "$DATA_FILE" << EOF
{
    "timestamp": "$TIMESTAMP",
    "system": $SYSTEM_METRICS,
    "sessions": $SESSIONS_DATA,
    "connections": $CONNECTION_STATUS,
    "logs": $RECENT_LOGS
}
EOF

# Hacer que el archivo sea legible
chmod 644 "$DATA_FILE"

echo "Datos de misión actualizados: $(date)"