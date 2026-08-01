import sqlite3
conn = sqlite3.connect('/home/project-lumina/Project-Lumina/data/hub.db')
print(conn.execute("SELECT sql FROM sqlite_master WHERE tbl_name='scholars'").fetchone())
print(conn.execute("SELECT sql FROM sqlite_master WHERE tbl_name='sessions'").fetchone())
print(conn.execute("SELECT sql FROM sqlite_master WHERE tbl_name='refresh_tokens'").fetchone())
print(conn.execute("SELECT sql FROM sqlite_master WHERE tbl_name='persistent_keys'").fetchone())
# Check for duplicate usernames
c = conn.cursor()
c.execute('SELECT username, COUNT(*) as cnt FROM scholars GROUP BY username HAVING cnt > 1')
dupes = c.fetchall()
print(f'Duplicate usernames: {dupes}')
c.execute('SELECT username, COUNT(*) as cnt FROM users GROUP BY username HAVING cnt > 1')
dupes2 = c.fetchall()
print(f'Duplicate admin/teacher usernames: {dupes2}')
