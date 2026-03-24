import { createContext, useContext, useEffect, useRef, useState } from "react";
import type { ContextMenuOption } from "../types";
import "./context.css";

interface MenuState {
  x: number;
  y: number;
  visible: boolean;
  options: ContextMenuOption[];
  callerElement: HTMLElement | null;
}

interface OpenMenuParams {
  e: React.MouseEvent<HTMLElement>;
  options: ContextMenuOption[];
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

  // 🔥 constants (your exact sizes)
  const MENU_WIDTH = 195;
  const ITEM_HEIGHT = 38;
  const CONTAINER_PADDING = 20; // 10 top + 10 bottom
  const EDGE_PADDING = 10;

  /* ---------------- OPEN MENU ---------------- */

  const openMenu = ({ e, options }: OpenMenuParams) => {
    e.preventDefault();

    const clickX = e.clientX;
    const clickY = e.clientY;

    const menuHeight = options.length * ITEM_HEIGHT + CONTAINER_PADDING;

    let x = clickX;
    let y = clickY;

    // clamp right
    if (x + MENU_WIDTH > window.innerWidth - EDGE_PADDING) {
      x = window.innerWidth - MENU_WIDTH - EDGE_PADDING;
    }

    // clamp bottom
    if (y + menuHeight > window.innerHeight - EDGE_PADDING) {
      y = window.innerHeight - menuHeight - EDGE_PADDING;
    }

    setMenu({
      x,
      y,
      visible: true,
      options,
      callerElement: e.currentTarget,
    });
  };

  /* ---------------- CLOSE MENU ---------------- */

  const closeMenu = () => {
    setMenu((prev) => ({
      ...prev,
      visible: false,
      options: [],
      callerElement: null,
    }));
  };

  /* ---------------- CLICK OUTSIDE ---------------- */

  useEffect(() => {
    const handlePointerDown = (e: PointerEvent) => {
      // ✅ ignore right-click only
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

  /* ---------------- SCROLL CLOSE ---------------- */

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

  /* ---------------- RENDER ---------------- */

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
          }}
          onContextMenu={(e) => {
            e.preventDefault();

            const clickX = e.clientX;
            const clickY = e.clientY;

            const menuHeight =
              menu.options.length * ITEM_HEIGHT + CONTAINER_PADDING;

            let x = clickX;
            let y = clickY;

            if (x + MENU_WIDTH > window.innerWidth - EDGE_PADDING) {
              x = window.innerWidth - MENU_WIDTH - EDGE_PADDING;
            }

            if (y + menuHeight > window.innerHeight - EDGE_PADDING) {
              y = window.innerHeight - menuHeight - EDGE_PADDING;
            }

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

/* ---------------- HOOK ---------------- */

export const useContextMenu = () => {
  const ctx = useContext(ContextMenuContext);
  if (!ctx) {
    throw new Error("Context must be used inside ContextMenuProvider");
  }
  return ctx;
};