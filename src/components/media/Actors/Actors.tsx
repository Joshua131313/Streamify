import type { TMDBCastPerson } from "../../../types/TMDBMediaType"
import { Container } from "../../layout/Container/Container"
import { ActorCard } from "./ActorCard";
import "./Actors.css"

interface Props {
    actors: TMDBCastPerson[] | undefined;
}

export const Actors = (props: Props) => {
    const { actors } = props;
    const actorsRow = actors?.map(actor => {
        return (
            <ActorCard actor={actor}/>
        )
    })

    return (
        <Container title="Actors" className="actors" containerId="actors">
            {actorsRow}
        </Container>
    )
}