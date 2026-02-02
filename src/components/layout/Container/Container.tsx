import { AccentLine } from "../../ui/AccentLine/AccentLine"
import "./Container.css"

interface Props {
    title?: string;
    children?: React.ReactNode;
    className?: string;
}

export const Container = (props : Props) => {

    const { title, className } = props

    return (
        <div className={`app-container ${className}`}>
            {
            title && 
                <div className="container-title">
                    <AccentLine />
                    <h1>{title}</h1>
                </div>
            }
            <div className="container-content">
                {props.children}
            </div>
        </div>
    )
}