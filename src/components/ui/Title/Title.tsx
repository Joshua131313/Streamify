import { AccentLine } from "../AccentLine/AccentLine"
import "./Title.css"

export const Title = ({title, id, className} : {title: string, id?: string, className?: string}) => {

    return (
        <div className={`title ${className}`} id={id}>
            <AccentLine />
            <h1>{title}</h1>
        </div>
    )
}