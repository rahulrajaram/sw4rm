/**
 * Diagram Fullscreen Modal
 * Enables click-to-expand functionality for diagrams
 */

document.addEventListener('DOMContentLoaded', function() {
    // Wait for Mermaid to render, then set up click handlers
    // Try multiple times with increasing delays
    setTimeout(setupDiagramHandlers, 500);
    setTimeout(setupDiagramHandlers, 1500);
    setTimeout(setupDiagramHandlers, 3000);
});

function setupDiagramHandlers() {
    // Find all existing diagram containers (manually wrapped)
    const existingContainers = document.querySelectorAll('.diagram-container');
    
    existingContainers.forEach(function(container) {
        // Skip if already has handler
        if (container.hasAttribute('data-fullscreen-handler')) {
            return;
        }
        
        // Look for any diagram-like content
        const hasAnyDiagramContent = container.querySelector('svg') || 
                                   container.querySelector('img') ||
                                   container.querySelector('.mermaid') ||
                                   container.querySelector('code[class*="language-"]') ||
                                   container.querySelector('pre');
        
        if (hasAnyDiagramContent) {
            // Mark as having handler and add click event
            container.setAttribute('data-fullscreen-handler', 'true');
            container.style.cursor = 'zoom-in';
            
            container.addEventListener('click', function(e) {
                e.preventDefault();
                e.stopPropagation();
                openFullscreenModal(this);
            });
        }
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
    
    // Handle Mermaid diagrams that aren't already wrapped
    const mermaidDiagrams = document.querySelectorAll('.mermaid:not(.diagram-container .mermaid)');
    
    mermaidDiagrams.forEach(function(mermaidDiv) {
        // Skip if already wrapped
        if (mermaidDiv.closest('.diagram-container')) {
            return;
        }
        
        const container = document.createElement('div');
        container.className = 'diagram-container';
        
        // Wrap the mermaid div
        mermaidDiv.parentNode.insertBefore(container, mermaidDiv);
        container.appendChild(mermaidDiv);
        
        // Add click handler
        container.addEventListener('click', function(e) {
            e.preventDefault();
            e.stopPropagation();
            openFullscreenModal(this);
        });
    });
}

function openFullscreenModal(diagramContainer) {
    // Create modal if it doesn't exist
    let modal = document.getElementById('diagram-fullscreen-modal');
    if (!modal) {
        modal = createModal();
    }
    
    // Get the diagram content
    const diagramContent = diagramContainer.querySelector('img, svg, pre');
    if (!diagramContent) {
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