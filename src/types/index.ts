import type { IconType } from "react-icons";

export interface MenuOption {
    value: string;
    key: string;
    onClick: () => void;
    icon: IconType
}