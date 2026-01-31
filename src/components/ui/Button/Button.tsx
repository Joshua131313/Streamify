import type { ButtonHTMLAttributes } from "react"
import "./Button.css"

interface Props extends ButtonHTMLAttributes<HTMLButtonElement> {

}

export const Button = (props : Props) => {
    return (
        <button {...props} className={`button ${props.className}`} >
            {props.children}
        </button>
    )
}