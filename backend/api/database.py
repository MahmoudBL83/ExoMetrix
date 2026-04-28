import os
import sqlite3
import hashlib
import secrets
from datetime import datetime
from pathlib import Path

DB_PATH = Path(__file__).parent / 'exometrix.db'


def get_db():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    return conn


def init_db():
    conn = get_db()
    cursor = conn.cursor()
    
    # Users table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS users (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            username TEXT UNIQUE NOT NULL,
            password_hash TEXT NOT NULL,
            email TEXT,
            created_at TEXT NOT NULL
        )
    ''')
    
    # Sessions table
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS sessions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            user_id INTEGER NOT NULL,
            name TEXT,
            started_at TEXT NOT NULL,
            ended_at TEXT,
            good_steps INTEGER DEFAULT 0,
            bad_steps INTEGER DEFAULT 0,
            total_samples INTEGER DEFAULT 0,
            avg_angle REAL DEFAULT 0.0,
            FOREIGN KEY (user_id) REFERENCES users(id) ON DELETE CASCADE
        )
    ''')
    
    # Predictions table (individual predictions within a session)
    cursor.execute('''
        CREATE TABLE IF NOT EXISTS predictions (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            session_id INTEGER NOT NULL,
            timestamp TEXT NOT NULL,
            angle REAL NOT NULL,
            model_score REAL,
            anomaly_strength REAL,
            classification TEXT,
            assistance_percent REAL,
            activity_class TEXT,
            intention_class TEXT,
            FOREIGN KEY (session_id) REFERENCES sessions(id) ON DELETE CASCADE
        )
    ''')
    
    conn.commit()
    conn.close()
    print(f"Database initialized at: {DB_PATH}")


def hash_password(password: str) -> str:
    return hashlib.sha256(password.encode()).hexdigest()


def generate_token() -> str:
    return secrets.token_hex(32)


def register_user(username: str, password: str, email: str = None) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    try:
        cursor.execute('''
            INSERT INTO users (username, password_hash, email, created_at)
            VALUES (?, ?, ?, ?)
        ''', (username, hash_password(password), email, datetime.now().isoformat()))
        
        user_id = cursor.lastrowid
        token = generate_token()
        conn.commit()
        conn.close()
        
        return {'success': True, 'user_id': user_id, 'token': token, 'username': username}
    except sqlite3.IntegrityError:
        conn.close()
        return {'success': False, 'error': 'Username already exists'}


def login_user(username: str, password: str) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, username FROM users 
        WHERE username = ? AND password_hash = ?
    ''', (username, hash_password(password)))
    
    row = cursor.fetchone()
    conn.close()
    
    if row:
        token = generate_token()
        return {'success': True, 'user_id': row['id'], 'token': token, 'username': row['username']}
    else:
        return {'success': False, 'error': 'Invalid username or password'}


def create_session(user_id: int, name: str = None) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO sessions (user_id, name, started_at)
        VALUES (?, ?, ?)
    ''', (user_id, name, datetime.now().isoformat()))
    
    session_id = cursor.lastrowid
    conn.commit()
    conn.close()
    
    return {'success': True, 'session_id': session_id}


def get_user_sessions(user_id: int) -> list:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT id, name, started_at, ended_at, good_steps, bad_steps, total_samples, avg_angle
        FROM sessions 
        WHERE user_id = ?
        ORDER BY started_at DESC
    ''', (user_id,))
    
    rows = cursor.fetchall()
    conn.close()
    
    return [
        {
            'id': row['id'],
            'name': row['name'],
            'started_at': row['started_at'],
            'ended_at': row['ended_at'],
            'good_steps': row['good_steps'],
            'bad_steps': row['bad_steps'],
            'total_samples': row['total_samples'],
            'avg_angle': row['avg_angle'],
        }
        for row in rows
    ]


def get_session(session_id: int, user_id: int) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        SELECT * FROM sessions WHERE id = ? AND user_id = ?
    ''', (session_id, user_id))
    
    row = cursor.fetchone()
    conn.close()
    
    if row:
        return {
            'id': row['id'],
            'name': row['name'],
            'started_at': row['started_at'],
            'ended_at': row['ended_at'],
            'good_steps': row['good_steps'],
            'bad_steps': row['bad_steps'],
            'total_samples': row['total_samples'],
            'avg_angle': row['avg_angle'],
        }
    return None


def end_session(session_id: int, user_id: int, stats: dict) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        UPDATE sessions 
        SET ended_at = ?, good_steps = ?, bad_steps = ?, total_samples = ?, avg_angle = ?
        WHERE id = ? AND user_id = ?
    ''', (
        datetime.now().isoformat(),
        stats.get('good_steps', 0),
        stats.get('bad_steps', 0),
        stats.get('total_samples', 0),
        stats.get('avg_angle', 0.0),
        session_id,
        user_id
    ))
    
    conn.commit()
    conn.close()
    
    return {'success': True}


def delete_session(session_id: int, user_id: int) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        DELETE FROM sessions WHERE id = ? AND user_id = ?
    ''', (session_id, user_id))
    
    deleted = cursor.rowcount > 0
    conn.commit()
    conn.close()
    
    if deleted:
        return {'success': True, 'message': 'Session deleted'}
    else:
        return {'success': False, 'error': 'Session not found'}


def save_prediction(session_id: int, prediction: dict) -> dict:
    conn = get_db()
    cursor = conn.cursor()
    
    cursor.execute('''
        INSERT INTO predictions (session_id, timestamp, angle, model_score, anomaly_strength, 
        classification, assistance_percent, activity_class, intention_class)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    ''', (
        session_id,
        datetime.now().isoformat(),
        prediction.get('angle', 0.0),
        prediction.get('model_score', 0.0),
        prediction.get('anomaly_strength', 0.0),
        prediction.get('classification', 'unknown'),
        prediction.get('assistance_percent', 0.0),
        prediction.get('activity_class', 'unknown'),
        prediction.get('intention_class', 'walking'),
    ))
    
    conn.commit()
    conn.close()
    
    return {'success': True}


if __name__ == '__main__':
    init_db()