import type { IconType } from "react-icons"
import "./Icon.css"

interface Props {
    Icon: IconType;
    className?: string;
    onClick?: (e : any) => void;
}

export const Icon = ({Icon, className, onClick} : Props) => {
    
    return (
        <div className={`app-icon ${className}`} onClick={(e) => onClick && onClick(e)}>
            <Icon/>
        </div>
    )
}