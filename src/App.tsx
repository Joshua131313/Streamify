import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';
import { useEffect } from 'react';
import { ContextMenuProvider } from './context/ContextMenu';

function App() {
  useMouseIdle();

  return (
    <AppProvider>
      <ContextMenuProvider>
        <AppRouter />
      </ContextMenuProvider>
    </AppProvider>
  )
}

export default App;
