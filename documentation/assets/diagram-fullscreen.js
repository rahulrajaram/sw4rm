/**
 * Diagram Fullscreen Modal
 * Enables click-to-expand functionality for diagrams
 */

document.addEventListener('DOMContentLoaded', function() {
    // Find all existing diagram containers (manually wrapped)
    const existingContainers = document.querySelectorAll('.diagram-container');
    
    existingContainers.forEach(function(container) {
        // Add click handler to existing containers
        container.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            openFullscreenModal(this);
        });
    });
    
    // Find all kroki diagrams that aren't already wrapped
    const diagrams = document.querySelectorAll('pre code[class*="language-kroki"]');
    
    diagrams.forEach(function(diagram) {
        // Skip if already wrapped
        if (diagram.closest('.diagram-container')) {
            return;
        }
        
        const container = document.createElement('div');
        container.className = 'diagram-container';
        container.setAttribute('data-diagram-source', diagram.textContent);
        
        // Wrap the diagram
        diagram.parentNode.parentNode.insertBefore(container, diagram.parentNode);
        container.appendChild(diagram.parentNode);
        
        // Add click handler
        container.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            openFullscreenModal(this);
        });
    });
    
    // Also handle images that might be generated diagrams
    const diagramImages = document.querySelectorAll('img[src*="kroki"], img[alt*="diagram"], img[alt*="architecture"]');
    
    diagramImages.forEach(function(img) {
        // Skip if already wrapped
        if (img.closest('.diagram-container')) {
            return;
        }
        
        const container = document.createElement('div');
        container.className = 'diagram-container';
        
        // Wrap the image
        img.parentNode.insertBefore(container, img);
        container.appendChild(img);
        
        // Add click handler
        container.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            openFullscreenModal(this);
        });
    });
});

function openFullscreenModal(diagramContainer) {
    // Create modal if it doesn't exist
    let modal = document.getElementById('diagram-fullscreen-modal');
    if (!modal) {
        modal = createModal();
    }
    
    // Get the diagram content
    const diagramContent = diagramContainer.querySelector('img, svg, pre');
    if (!diagramContent) {
        console.warn('No diagram content found');
        return;
    }
    
    // Clone the diagram for the modal
    const modalContent = modal.querySelector('.fullscreen-modal-content');
    const clonedDiagram = diagramContent.cloneNode(true);
    
    // Clear previous content and add new diagram
    const existingDiagram = modalContent.querySelector('img, svg, pre');
    if (existingDiagram) {
        existingDiagram.remove();
    }
    
    modalContent.appendChild(clonedDiagram);
    
    // Show modal
    modal.classList.add('active');
    document.body.style.overflow = 'hidden';
}

function closeFullscreenModal() {
    const modal = document.getElementById('diagram-fullscreen-modal');
    if (modal) {
        modal.classList.remove('active');
        document.body.style.overflow = '';
    }
}

function createModal() {
    const modal = document.createElement('div');
    modal.id = 'diagram-fullscreen-modal';
    modal.className = 'fullscreen-modal';
    
    modal.innerHTML = `
        <div class="fullscreen-modal-content">
            <button class="fullscreen-modal-close" onclick="closeFullscreenModal()">&times;</button>
        </div>
    `;
    
    document.body.appendChild(modal);
    
    // Close on background click
    modal.addEventListener('click', function(e) {
        if (e.target === modal) {
            closeFullscreenModal();
        }
    });
    
    // Close on Escape key
    document.addEventListener('keydown', function(e) {
        if (e.key === 'Escape' && modal.classList.contains('active')) {
            closeFullscreenModal();
        }
    });
    
    return modal;
}

// Expose functions globally
window.closeFullscreenModal = closeFullscreenModal;