import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';
import { useEffect } from 'react';
import { ContextMenuProvider } from './context/ContextMenu';
import { QuickWatchProvider } from './context/MultiWatchContext';
import { SportsProvider } from './context/SportsContext';
import { MultiWatch } from './pages/Sports/MultiWatch';

function App() {
  useMouseIdle();

  return (
    <AppProvider>
      <ContextMenuProvider>
        <QuickWatchProvider>
       
          <SportsProvider>   <MultiWatch />
            <AppRouter />
          </SportsProvider>
        </QuickWatchProvider>
      </ContextMenuProvider>
    </AppProvider>
  )
}

export default App;
