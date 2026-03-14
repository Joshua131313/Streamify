import type { TMDBCastPerson, TMDBMediaCredits } from "../../../types/TMDBMediaType"
import { Container } from "../../layout/Container/Container"
import "./Credits.css"

interface Props {
    children: React.ReactNode;
    containerId: string;
    title: string;
    className: string;
}

export const Credits = (props: Props ) => {
    const { containerId, title, className } = props;

    return (
        <Container accordionMode title={title} className={`credits ${className}`} containerId={containerId}>
            {props.children}
        </Container>
    )
}