CREATE TABLE conversations (
  id SERIAL PRIMARY KEY,
  chat_id BIGINT NOT NULL,
  role VARCHAR(20) NOT NULL,
  content TEXT NOT NULL,
  created_at TIMESTAMP DEFAULT NOW()
);
