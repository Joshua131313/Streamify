import type { IconType } from "react-icons";

export interface ContextMenuOption {
    value: string;
    key: string;
    onClick: () => void;
    icon: IconType
}