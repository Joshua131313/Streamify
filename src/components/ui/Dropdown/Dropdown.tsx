import { useEffect, useRef, useState } from "react";
import type { MenuOption } from "../../../types";
import "./Dropdown.css"

interface Props {
    children: React.ReactNode;
    dropdownOptions: MenuOption[];
    title: string;
    className?: string;
}


export const Dropdown = (props: Props) => {
    const { title, dropdownOptions, className } = props;
    const menuRef = useRef<HTMLDivElement | null>(null);
    const [dropdown, setDropdown] = useState(false);

    const dropdownOptionsRow = dropdownOptions.map(option => {
        return (
            <div className="dropdown-option" onClick={() => {
                option.onClick();
            }}>
                <option.icon />
                <span>{option.value}</span>
            </div>
        )
    })

    useEffect(() => {
        const handlePointerDown = (e: PointerEvent) => {

            const target = e.target as Node;

            if (menuRef.current?.contains(target)) return;

            setDropdown(false);
        };

        document.addEventListener("pointerdown", handlePointerDown, true);

        return () => {
            document.removeEventListener("pointerdown", handlePointerDown, true);
        };
    }, []);

    return (
        <div className={`dropdown-wrapper ${className}`} ref={menuRef}>
            <div onClick={() => setDropdown(!dropdown)}>{props.children}</div>
            {
                dropdown &&
                <div className="dropdown-content">
                    <strong >{title}</strong>
                    <div className="dropdown-options">
                        {dropdownOptionsRow}
                    </div>
                </div>
            }
        </div>
    )
}