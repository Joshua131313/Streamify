import { useEffect, useRef, useState } from "react";
import type { MenuOption } from "../../../types";
import "./Dropdown.css"

interface Props {
    children: React.ReactNode;
    dropdownOptions: MenuOption[];
    title: string;
    subTitle?: string;
    className?: string;
    Footer?: React.ReactNode;
}


export const Dropdown = (props: Props) => {
    const { title, subTitle, dropdownOptions, className, Footer } = props;

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

    return (
        <div className={`dropdown-wrapper ${className}`}>
            <div className="dropdown-controller">{props.children}</div>
            <div className="dropdown-content">
                <div className="dropdown-header">
                    <strong >{title}</strong>
                    {subTitle && <small >{subTitle}</small>}
                </div>
                <div className="dropdown-options">
                    {dropdownOptionsRow}
                </div>
                {
                    Footer &&
                    <div className="dropdown-footer">
                        {Footer}
                    </div>
                }
            </div>

        </div>
    )
}