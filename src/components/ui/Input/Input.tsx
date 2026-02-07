import type { InputHTMLAttributes } from "react"
import type { IconType } from "react-icons"
import "./Input.css"
import { Button } from "../Button/Button";

interface Props extends InputHTMLAttributes<HTMLInputElement> {
    Icon?: IconType;
}

export const Input = (props: Props) => {
    const { Icon } = props;
    return (
        <div className={`input-container ${Icon ? "has-icon" : ""}`}>
            {Icon && <Icon className="icon"/>}
            <input type="text" {...props}/>
        </div>
    )
}