# EasyPaste 0.3.13

- Clic droit sur l’icône EasyPaste dans la barre des menus : ouvre ou ferme la barre rapide, comme ⇧⌘V. Le clic gauche conserve le menu habituel.
- Bitwarden : le partage d’un élément lance directement le déverrouillage local si nécessaire, puis reprend le contenu choisi sans repasser par le menu.
- Après authentification, le partage rapide conserve la confirmation « Lien copié » à l’écran. Le lien rejoint le presse-papiers, l’historique et la pile.
- Les partages avec options retrouvent leur formulaire après déverrouillage, sans envoi automatique.
- Nouveau réglage Bitwarden : verrouillage après 15 minutes, 1 heure ou 4 heures d’inactivité. La valeur par défaut reste 15 minutes ; la veille et le verrouillage du Mac verrouillent toujours la connexion immédiatement.
- Une session expirée permet de se reconnecter sans perdre l’élément à partager. Le minuteur d’inactivité est suspendu pendant une opération pour éviter une fermeture en cours d’authentification ou d’envoi.

Validation : 361 tests automatiques réussis, dont les parcours Bitwarden de reprise, d’annulation et de session expirée. Les tests Bitwarden utilisent un serveur simulé ; ils ne créent aucun partage réel.
