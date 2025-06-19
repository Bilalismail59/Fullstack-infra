import { useState, useEffect } from 'react'
import { Button } from '@/components/ui/button.jsx'
import { Card, CardContent, CardDescription, CardHeader, CardTitle } from '@/components/ui/card.jsx'
import { Badge } from '@/components/ui/badge.jsx'
import { Cloud, Server, Database, Shield, Monitor, GitBranch } from 'lucide-react'
import './App.css'

function App() {
  const [status, setStatus] = useState('Initializing...')
  const [services, setServices] = useState([
    { name: 'Frontend', status: 'running', icon: Cloud },
    { name: 'Backend', status: 'running', icon: Server },
    { name: 'Database', status: 'running', icon: Database },
    { name: 'Security', status: 'active', icon: Shield },
    { name: 'Monitoring', status: 'active', icon: Monitor },
    { name: 'CI/CD', status: 'active', icon: GitBranch }
  ])

  useEffect(() => {
    setTimeout(() => setStatus('All systems operational'), 1000)
  }, [])

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 p-8">
      <div className="max-w-6xl mx-auto">
        <header className="text-center mb-12">
          <h1 className="text-4xl font-bold text-gray-900 mb-4">
            Infrastructure Full Stack
          </h1>
          <p className="text-xl text-gray-600 mb-6">
            Architecture trois tiers sécurisée sur Google Cloud
          </p>
          <Badge variant="outline" className="text-lg px-4 py-2">
            {status}
          </Badge>
        </header>

        <div className="grid grid-cols-1 md:grid-cols-2 lg:grid-cols-3 gap-6 mb-12">
          {services.map((service, index) => {
            const IconComponent = service.icon
            return (
              <Card key={index} className="hover:shadow-lg transition-shadow">
                <CardHeader className="flex flex-row items-center space-y-0 pb-2">
                  <IconComponent className="h-6 w-6 text-blue-600 mr-2" />
                  <CardTitle className="text-lg">{service.name}</CardTitle>
                </CardHeader>
                <CardContent>
                  <Badge 
                    variant={service.status === 'running' ? 'default' : 'secondary'}
                    className="capitalize"
                  >
                    {service.status}
                  </Badge>
                </CardContent>
              </Card>
            )
          })}
        </div>

        <div className="grid grid-cols-1 lg:grid-cols-2 gap-8">
          <Card>
            <CardHeader>
              <CardTitle>Technologies utilisées</CardTitle>
              <CardDescription>Stack technique de l'infrastructure</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="flex flex-wrap gap-2">
                {['Terraform', 'Ansible', 'Kubernetes', 'Docker', 'Traefik', 'Prometheus', 'Grafana', 'SonarQube', 'GitHub Actions'].map((tech) => (
                  <Badge key={tech} variant="outline">{tech}</Badge>
                ))}
              </div>
            </CardContent>
          </Card>

          <Card>
            <CardHeader>
              <CardTitle>Environnements</CardTitle>
              <CardDescription>Gestion des déploiements</CardDescription>
            </CardHeader>
            <CardContent className="space-y-4">
              <div className="space-y-2">
                <div className="flex justify-between items-center">
                  <span>Pré-production</span>
                  <Badge variant="secondary">Actif</Badge>
                </div>
                <div className="flex justify-between items-center">
                  <span>Production</span>
                  <Badge variant="default">Déployé</Badge>
                </div>
              </div>
            </CardContent>
          </Card>
        </div>

        <footer className="text-center mt-12 text-gray-500">
          <p>Projet de déploiement automatisé avec supervision et sécurité renforcée</p>
        </footer>
      </div>
    </div>
  )
}

export default App
