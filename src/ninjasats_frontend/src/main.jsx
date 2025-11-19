import React from 'react';
import ReactDOM from 'react-dom/client';
import AppRouter from './Router';
import { AuthProvider } from './context/AuthContext';
import './index.scss';

ReactDOM.createRoot(document.getElementById('root')).render(
  <React.StrictMode>
    <AuthProvider>
      <AppRouter />
    </AuthProvider>
  </React.StrictMode>,
);
