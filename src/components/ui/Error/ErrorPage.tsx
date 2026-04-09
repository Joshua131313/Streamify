import { useNavigate } from "react-router-dom"
import { Container } from "../../layout/Container/Container"
import { Footer } from "../../layout/Footer/Footer"
import { Mobilebar } from "../../Navbar/Mobilebar"
import { Navbar } from "../../Navbar/Navbar"
import { Button } from "../Button/Button"
import "./ErrorBoundary.css"

export const ErrorPage = () => {
    const navigate = useNavigate();
    return (
        <>
            <Navbar />
            <Container  className="error-content">
                <h2>Page not found</h2>
                <Button onClick={() => navigate(-1)}>Go Back</Button>
            </Container>
            <Footer />
            <Mobilebar />
        </>
    )
}