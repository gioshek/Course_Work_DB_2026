import os
from contextlib import contextmanager
from typing import Any, Dict, List, Tuple

import pyodbc
from dotenv import load_dotenv


load_dotenv()


def build_connection_string() -> str:
    driver = os.getenv("DB_DRIVER", "ODBC Driver 18 for SQL Server")
    server = os.getenv("DB_SERVER", "localhost")
    database = os.getenv("DB_DATABASE", "BookStreamDB")
    user = os.getenv("DB_USER", "SA")
    password = os.getenv("DB_PASSWORD", "")
    encrypt = os.getenv("DB_ENCRYPT", "yes")
    trust_server_certificate = os.getenv("DB_TRUST_SERVER_CERTIFICATE", "yes")

    return (
        f"DRIVER={{{driver}}};"
        f"SERVER={server};"
        f"DATABASE={database};"
        f"UID={user};"
        f"PWD={password};"
        f"Encrypt={encrypt};"
        f"TrustServerCertificate={trust_server_certificate};"
        f"Connection Timeout=30;"
    )


@contextmanager
def get_connection():
    connection = None

    try:
        connection = pyodbc.connect(build_connection_string())
        yield connection
    finally:
        if connection is not None:
            connection.close()


def rows_to_dicts(cursor) -> List[Dict[str, Any]]:
    if cursor.description is None:
        return []

    columns = [column[0] for column in cursor.description]
    rows = cursor.fetchall()

    result = []
    for row in rows:
        result.append({columns[index]: row[index] for index in range(len(columns))})

    return result


def call_db(sql: str, params: Tuple[Any, ...] = ()) -> List[List[Dict[str, Any]]]:
    result_sets: List[List[Dict[str, Any]]] = []

    with get_connection() as connection:
        cursor = connection.cursor()

        try:
            cursor.execute(sql, *params)

            while True:
                if cursor.description is not None:
                    result_sets.append(rows_to_dicts(cursor))

                if not cursor.nextset():
                    break

            connection.commit()
            return result_sets

        except Exception:
            connection.rollback()
            raise