import { useState } from "react"
import { Button } from "../../components/ui/Button/Button"
import { Input } from "../../components/ui/Input/Input"
import { Auth } from "./Auth"


export const Register = () => {
    
    const [firstName, setFirstName] = useState("");
    const [lastName, setLastName] = useState("");
    const [email, setEmail] = useState("");
    const [password, setPassword] = useState("");
    

    const handleRegister = () => {
        
    }

    return (
        <Auth onSubmit={handleRegister} title="Login" type="login" childrenContainerClassName="login">
            <div className="name">
                <Input placeholder="First Name" value={firstName} onChange={(e) => setFirstName(e.target.value)}/>
                <Input placeholder="Last Name"/>
            </div>
            <Input placeholder="Email"/>
            <Input placeholder="Password"/>
            <Button>
                Register
            </Button>
        </Auth>
    )
}