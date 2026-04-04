import { AppRouter } from './router/AppRouter';
import { AppProvider } from './context/AppContext';
// @ts-ignore
import 'swiper/css';
import { useMouseIdle } from './hooks/utilHooks/useMouseIdle';
import { useEffect } from 'react';
import { ContextMenuProvider } from './context/ContextMenu';
import { SportsProvider } from './context/SportsContext';
import { MultiWatch } from './pages/Sports/MultiWatch';
import { MultiWatchProvider } from './context/MultiWatchContext';
import { WindowManagerProvider } from './context/WindowManagerContext';
import { WindowRenderer } from './components/ui/Window/WindowRenderer';
import { AuthProvider } from './context/AuthContext';

function App() {
  useMouseIdle();
// Add onboarding feature to ask favorite media genre, favorite sports team, 
  return (
    <AuthProvider>
      <AppProvider>
        <ContextMenuProvider>
          <WindowManagerProvider>
            <MultiWatchProvider>
              <SportsProvider>
                <WindowRenderer />
                {/* fake body container to allow windows to be "position fixed" */}
                <div className="body">
                  <AppRouter />
                </div>
              </SportsProvider>
            </MultiWatchProvider>
          </WindowManagerProvider>
        </ContextMenuProvider>
      </AppProvider>
    </AuthProvider>
  )
}

export default App;
