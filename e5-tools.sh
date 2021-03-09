[ "$OSTYPE" = "linux-gnu" ] || {
    IS_WINDOWS=true
}


export E5_ROOT_DIR_WINDOWS='c:/Program Files (x86)/1C Education/1CE5'
export E5_ROOT_DIR_LINUX='/opt/1CE5'


[ "$E5_BRANCH" = "oko" ] && {
    export E5_ROOT_DIR_WINDOWS='c:/Program Files (x86)/1C OKO'
    export E5_ROOT_DIR_LINUX='/opt/1COKO'
}


export E5_ROOT_DIR="$E5_ROOT_DIR_LINUX"


[ "$IS_WINDOWS" ] && {
    E5_ROOT_DIR="$E5_ROOT_DIR_WINDOWS"
}


export E5_CD_ROOT_DIR="{ cd '$E5_ROOT_DIR_LINUX' || cd '$E5_ROOT_DIR_WINDOWS'; } 2>/dev/null"


# server control


alias e5-server-status="ps -eH | sed -n '/StartServer/,/ java/ p'"
alias e5-server-stop="$E5_ROOT_DIR_LINUX/StopServer.sh"
alias e5-server-start="$E5_ROOT_DIR_LINUX/StartServer.sh &"
alias e5-server-restart='e5-server-stop; sleep 10; e5-server-start'


[ "$IS_WINDOWS" ] && {
    alias posh='c:/Windows/System32/WindowsPowerShell/v1.0/powershell.exe -ExecutionPolicy Bypass'
    alias e5-server-status='posh "Get-Service *1c*"'
    alias e5-server-stop='posh "Get-Service *1c* | Stop-Service -Verbose" ; e5-server-status'
    alias e5-server-start='posh "Get-Service *1c* | Start-Service -Verbose" ; e5-server-status'
    alias e5-server-restart='e5-server-stop; sleep 10; e5-server-start'
}


# dbutils


function dbutils() {
    "$E5_ROOT_DIR/DBUtils.sh" "$@"
}


if [ "$IS_WINDOWS" ]; then
    function dbutils() {
        local -
        set -o pipefail
        "$E5_ROOT_DIR/1CEduWeb/utils/1CE5DbUtils" "$@" |& iconv -f cp866 -t utf-8
    }
fi


# e5-specific SQL client


function e5-isql() {
    local OPTIND=1
    while getopts "hc:r:i" o; do
        case $o in
            c) local sql="$OPTARG";;
            r) local ssh_spec=$OPTARG;;
            i) local in_place=true;;
            h)
                echo 'Usage: e5-isql [-c <one-off sql command>]'
                echo '               [-r <remote hosts spec>] # e.g. user@host'
                echo '               [-i] # Edit db in-place'
                echo '               [-h] # Show help and exit'
                echo '               <path-to-db> # Relative to 1CEduWeb/data'
                return 0
                ;;
            ?) isql-e5 -h ; return 1 ;;
        esac
    done
    shift $(($OPTIND - 1))
    [ "$1" ] || { isql-e5 -h ; return 0; }
    local db_original="$1"
    local db_copy="$1"
    local cd_data_dir="$E5_CD_ROOT_DIR ; cd 1CEduWeb/data"
    local fetch_command="$cd_data_dir"" ; cat '$db_original'"

    # Fetch db
    [ "$ssh_spec" ] && fetch_command="ssh $ssh_spec \"$fetch_command\""
    [ "$ssh_spec" ] || [ -z "$in_place" ] && {
        local db_tmp=$(mktemp)
        bash -c "$fetch_command" > $db_tmp
        db_copy=$db_tmp
    }

    # Exec sql / start REPL
    local isql=isql
    [ "$OSTYPE" = "linux-gnu" ] && isql=isql-fb
    local isql_command="$isql -user sysdba -password masterkey $db_copy"
    [ "$sql" ] && {
        local sql_script=$(mktemp)
        echo "$sql" > $sql_script
        isql_command="$isql_command -i $sql_script"
    }
    bash -c "$isql_command"

    # Push db to remote host (if necessary)
    [ "$in_place" ] && [ "$ssh_spec" ] && {
        ssh $ssh_spec "$cd_data_dir"" ; cat > '$db_original'" < $db_copy
    }

    # # Clean up
    [ "$sql_script" ] && rm $sql_script
    [ "$db_tmp" ] && rm $db_tmp
}


# Messing with logs


function e5-logs-dump() {
    local OPTIND=1
    while getopts "hd:r:" o; do
        case $o in
            d) local dump_file="$(readlink -f "$OPTARG/logs_$(date '+%F_%H%M%S').tar.gz")";;
            r) local ssh_spec=$OPTARG;;
            h)
                echo 'Usage: e5-logs-dump [-d <directory where place logs .tar.gz>]'
                echo '                    # By default, dumping tar stream into stdout'
                echo '                    [-r <remote hosts spec, e.g. user@host>]'
                return 0 ;;
            ?) dump-e5-logs -h ; return 1 ;;
        esac
    done
    local command="$E5_CD_ROOT_DIR ; tar -cz 1CEduWeb/webapps/1CEduWeb/WEB-INF/{ls.xml,web.xml,log} 1CEduWeb/app*/build.properties common/jetty/etc/{*.properties,*.xml} common/jetty/logs"
    [ "$ssh_spec" ] && command="ssh $ssh_spec \"$command\""
    [ "$dump_file" ] && {
        bash -c "$command" > "$dump_file"
        echo "$dump_file"
        return $?
    }
    bash -c "$command"
}


function e5-logs-delete() {
    bash -c "$E5_CD_ROOT_DIR ; rm -rv 1CEduWeb/webapps/1CEduWeb/WEB-INF/log common/jetty/logs/*"
}


# dlr loader

function dlrloader() {
    local OPTIND=1
    while getopts "hs:p:t:" o; do
        case $o in
            t) local thread_count=$OPTARG;;
            s) local host=$OPTARG;;
            p) local port=$OPTARG;;
            h)
                echo 'Usage: dlrloader [-t <thread count>]'
                echo '                 [-s <host>]'
                echo '                 [-p <port>]'
                echo 'For custom dlrloader base folder, use E5_DLR_LOADER_HOME env variable'
                return 0
        esac
    done
    local E5_DLR_LOADER_HOME="${E5_DLR_LOADER_HOME:-$E5_ROOT_DIR/1CEduWeb/app}"
    local settings_file="$E5_DLR_LOADER_HOME/config/ConnectionProperties.xml"

    local thread_count=${thread_count:-4}
    local host=${host:-localhost}
    local port=${port:-8095}
    local thread_count_option='<entry key="loaderThreadsCount">'"$thread_count"'</entry>'
    local host_option='<entry key="host">'"$host"'</entry>'
    local port_option='<entry key="port">'"$port"'</entry>'

    sed -e '/"loaderThreadsCount"/ d' \
        -e '/"port"/ d' \
        -e '/"host"/ d' \
        -e '/<properties/ a '"$thread_count_option" \
        -e '/<properties/ a '"$port_option" \
        -e '/<properties/ a '"$host_option" \
        -i \
        "$settings_file"
    cat "$settings_file"
    "$E5_DLR_LOADER_HOME/dlrloader/1CE5Loader.exe" &
}
