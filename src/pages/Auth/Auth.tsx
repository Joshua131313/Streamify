import { Link, Navigate, useNavigate } from "react-router-dom";
import { Container } from "../../components/layout/Container/Container"
import "./Auth.css"
import { Button } from "../../components/ui/Button/Button";
import GoogleIcon from "./GoogleIcon";
import AppleIcon from "./AppleIcon";
import { useAuthProvider, type ProviderType } from "../../context/AuthContext";
import { useEffect } from "react";
interface Props {
    type: "login" | "register";
    children: React.ReactNode;
    childrenContainerClassName: string;
    title: string;
    onSubmit: () => void;
    header: {
        title: string;
        link: {
            label: string;
            to: string;
        }
    }
}

export const Auth = (props: Props) => {
    const { childrenContainerClassName, title, type, onSubmit, header } = props;
    const { loginWithProvider, user } = useAuthProvider();
    const navigate = useNavigate();
    const handleLoginWithProvider = async (provider: ProviderType) => {
        try {
            await loginWithProvider(provider);
            navigate("/");
        }
        catch (err) {

        }
    }

    return (
        <Container className="auth" styled>
            {user && <Navigate to={"/"} />}
            <div className="auth-bg">
                <img src="/images/auth-bg.jpg" />
            </div>
            <div className={`auth-form ${childrenContainerClassName}`}>
                <div className="auth-header">
                    <h1>{title}</h1>
                    <span>{header.title} <Link to={header.link.to}>{header.link.label}</Link></span>
                </div>
                <form onSubmit={(e) => {
                    e.preventDefault();
                    onSubmit();
                }}>
                    {props.children}
                </form>
                <div className="divider">
                    <span>Or continue with</span>
                </div>
                <div className="auth-providers">
                    <Button className="secondary" onClick={() => handleLoginWithProvider("google")}>
                        <GoogleIcon />
                        <span>Continue with Google</span>
                    </Button>
                    <Button className="secondary" onClick={() => handleLoginWithProvider("apple")}>
                        <AppleIcon />
                        <span>Continue with Apple</span>
                    </Button>
                </div>
            </div>
        </Container>
    )
}