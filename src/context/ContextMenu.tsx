import { createContext, useContext, useEffect, useRef, useState } from "react";
import type { MenuOption } from "../types";

interface MenuState {
  x: number;
  y: number;
  visible: boolean;
  options: MenuOption[];
  callerElement: HTMLElement | null;
}

interface OpenMenuParams {
  e: React.MouseEvent<HTMLElement>;
  options: MenuOption[];
}

interface ContextMenuType {
  openMenu: (params: OpenMenuParams) => void;
  closeMenu: () => void;
}

const ContextMenuContext = createContext<ContextMenuType | null>(null);

export const ContextMenuProvider = ({
  children,
}: {
  children: React.ReactNode;
}) => {
  const [menu, setMenu] = useState<MenuState>({
    x: 0,
    y: 0,
    visible: false,
    options: [],
    callerElement: null,
  });

  const menuRef = useRef<HTMLDivElement | null>(null);

  const MENU_WIDTH = 235;
  const ITEM_HEIGHT = 38;
  const CONTAINER_PADDING = 20;
  const EDGE_PADDING = 10;
  const BOTTOM_PADDING = 20;


  const getMenuPosition = (clickX: number, clickY: number, optionCount: number) => {
    const menuHeight = optionCount * ITEM_HEIGHT + CONTAINER_PADDING;

    let x = clickX;
    let y = clickY;

    if (clickX + MENU_WIDTH > window.innerWidth - EDGE_PADDING) {
      x = clickX - MENU_WIDTH; 
    } else {
      x = clickX;
    }

    if (x < EDGE_PADDING) {
      x = EDGE_PADDING;
    }


    if (clickY + menuHeight > window.innerHeight - EDGE_PADDING) {
      y = clickY - menuHeight - BOTTOM_PADDING;
    } else {
      y = clickY;
    }

    if (y < EDGE_PADDING) {
      y = EDGE_PADDING;
    }

    return { x, y };
  };

  const openMenu = ({ e, options }: OpenMenuParams) => {
    e.preventDefault();

    const { x, y } = getMenuPosition(e.clientX, e.clientY, options.length);

    setMenu({
      x,
      y,
      visible: true,
      options,
      callerElement: e.currentTarget,
    });
  };


  const closeMenu = () => {
    setMenu((prev) => ({
      ...prev,
      visible: false,
      options: [],
      callerElement: null,
    }));
  };


  useEffect(() => {
    const handlePointerDown = (e: PointerEvent) => {
      if (e.button === 2) return;

      const target = e.target as Node;

      if (menuRef.current?.contains(target)) return;

      setMenu((prev) => {
        if (!prev.visible) return prev;

        return {
          ...prev,
          visible: false,
          options: [],
          callerElement: null,
        };
      });
    };

    document.addEventListener("pointerdown", handlePointerDown, true);

    return () => {
      document.removeEventListener("pointerdown", handlePointerDown, true);
    };
  }, []);


  useEffect(() => {
    const handleScroll = () => {
      setMenu((prev) => {
        if (!prev.visible) return prev;

        return {
          ...prev,
          visible: false,
          options: [],
          callerElement: null,
        };
      });
    };

    window.addEventListener("scroll", handleScroll, true);

    return () => {
      window.removeEventListener("scroll", handleScroll, true);
    };
  }, []);


  return (
    <ContextMenuContext.Provider value={{ openMenu, closeMenu }}>
      {children}

      {menu.visible && (
        <div
          ref={menuRef}
          className="context-menu"
          style={{
            top: menu.y,
            left: menu.x,
            position: "fixed",
            width: MENU_WIDTH,
            minWidth: MENU_WIDTH
          }}
          onContextMenu={(e) => {
            e.preventDefault();

            const { x, y } = getMenuPosition(
              e.clientX,
              e.clientY,
              menu.options.length
            );

            setMenu((prev) => ({
              ...prev,
              x,
              y,
            }));
          }}
        >
          {menu.options.map((opt) => (
            <div
              className="context-option"
              key={opt.key}
              onClick={() => {
                opt.onClick?.();
                closeMenu();
              }}
            >
              <opt.icon />
              <span>{opt.value}</span>
            </div>
          ))}
        </div>
      )}
    </ContextMenuContext.Provider>
  );
};


export const useContextMenu = () => {
  const ctx = useContext(ContextMenuContext);
  if (!ctx) {
    throw new Error("Context must be used inside ContextMenuProvider");
  }
  return ctx;
};