import { Container } from "../Container/Container"
import "./Footer.css"

export const Footer = ()  => {

    return (
        <>
        <Container className="footer">
            Streamify does not own any media, uses an API to display content.
        </Container>
        <div className="mobile-bar-spacer"></div>
        </>
    )
}